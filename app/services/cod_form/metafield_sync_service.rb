# frozen_string_literal: true

require "json"
require "digest"

module CodForm
  # Writes the `codk.cod_form` shop metafield (C.1) whenever `config_version > metafield_synced_version`.
  #
  #   CodForm::MetafieldSyncService.call(shop)               # no-op when already in sync
  #   CodForm::MetafieldSyncService.call(shop, force: true)  # kill switch, cap state change, Setting change
  #
  # The payload itself is built by the pure CodForm::Engine::MetafieldPayload.build(input) (WS2);
  # this class gathers the input. `build_input` and `features` are pure (plain hashes) and are
  # unit-tested without Rails: ruby test/services/cod_form/metafield_sync_service_test.rb
  class MetafieldSyncService
    NAMESPACE = "codk"
    KEY = "cod_form"
    DIGEST_TTL = 604_800 # 7 days, seconds
    CONTENT_BLOCK_TYPES = %w[rich_text image trust_badges countdown].freeze

    class << self
      # => {status: :synced | :noop | :failed, version: Integer}
      #
      # The job is also enqueued without a version bump (cap state change, COD-rule / COD-fee
      # change on Setting, kill switch), so "nothing to do" is decided on the payload itself: a
      # digest of the last payload written is kept in CodForm::Cache.store. `v` is part of the payload, so
      # `config_version > metafield_synced_version` always produces a new digest.
      def call(shop, force: false)
        config = CodForm::ShopConfig.for(shop)
        version = config.config_version
        payload = payload_for(shop, config)
        digest = Digest::SHA256.hexdigest(JSON.generate(payload))
        if !force && !config.metafield_stale? && config.metafield_synced_at.present? &&
           CodForm::Cache.store.read(digest_key(shop)) == digest
          return { status: :noop, version: version }
        end

        if write(shop, payload)
          # `version` was read before the payload was built: a write that lands meanwhile bumps
          # config_version again and enqueues another run.
          config.mark_metafield_synced!(version)
          CodForm::Cache.store.write(digest_key(shop), digest, expires_in: DIGEST_TTL)
          sync_payment_function(shop, config)
          { status: :synced, version: version }
        else
          { status: :failed, version: version }
        end
      end

      def digest_key(shop)
        "codf:mf:digest:#{shop.id}"
      end

      # The C.1 hash for a shop (also used by tests in a console: no Shopify call).
      def payload_for(shop, config = CodForm::ShopConfig.for(shop))
        payload = CodForm::Engine::MetafieldPayload.build(build_input(facts_for(shop, config)))
        early = early_form(shop, payload)
        early ? payload.merge("early" => early) : payload
      end

      EARLY_MAX_BYTES = 16_000
      EARLY_MAX_COUNTRIES = 8

      # `early`: the published form and the address rules of the form's countries, printed into
      # product and cart pages by the embed so the fields can be drawn the instant the buyer taps
      # the button, with no request at all. Same content as GET /api/form/config; the session
      # still decides everything. nil when the early form could differ from the session's
      # (several active forms: the session picks one by targeting) or would be too large.
      def early_form(shop, payload)
        return nil unless payload["enabled"] == true

        forms = CodForm::Form.where(shop_id: shop.id).active.ordered.limit(2).to_a
        return nil unless forms.size == 1

        form = forms.first
        return nil unless form.published_config.is_a?(Hash) && form.published_config.any?

        any_country = Array(payload["countries"]).empty?
        codes = any_country ? [shop.country_code.to_s.upcase] : Array(payload["countries"])
        codes = codes.select { |code| code.match?(/\A[A-Z]{2}\z/) }
        return nil if codes.empty? || codes.size > EARLY_MAX_COUNTRIES

        early = {
          "form" => { "id" => form.id, "version" => form.published_version, "config" => form.published_config },
          "countries" => CodForm::CatalogService.countries_for({ "countries" => codes }, codes.first),
          "schemas" => codes.to_h { |code| [code, CodForm::CatalogService.country_schema(code)] },
          "any_country" => any_country,
          "pricing" => early_pricing(shop, form)
        }
        JSON.generate(early).bytesize > EARLY_MAX_BYTES ? nil : early
      rescue StandardError => e
        Rails.logger.warn("[CodForm::MetafieldSyncService] early form skipped shop_id=#{shop.id} #{e.class}")
        nil
      end

      # What the browser needs to price the first view before the session answers: the COD fee and
      # the shipping rates when every rate depends only on the address and the subtotal (weight,
      # quantity or product conditions need the server, so "rates" is then nil). Shop currency only.
      DEVICE_RATE_KEYS = %w[countries provinces subtotal_min_cents subtotal_max_cents].freeze

      def early_pricing(shop, form)
        setting = shop.setting
        rates = CodForm::ShippingRate.where(shop_id: shop.id).active.ordered.map(&:to_engine_hash)
        device = rates.all? do |rate|
          cond = rate["conditions"].is_a?(Hash) ? rate["conditions"] : {}
          cond.all? do |key, value|
            DEVICE_RATE_KEYS.include?(key.to_s) || value.blank? ||
              (key.to_s == "products" && value.is_a?(Hash) && Array(value["product_ids"]).empty? && Array(value["collection_ids"]).empty?)
          end
        end
        {
          "currency" => shop.try(:currency).to_s.upcase.presence,
          "fee" => CodForm::CodFeeAdapter.from_setting(setting, currency: nil, shop_currency: nil).slice("enabled", "mode", "value", "label"),
          "rates" => device ? rates.map { |rate| rate.slice("id", "name", "description", "price_cents", "currency", "position", "conditions") } : nil,
          "hide_single" => ((form.published_config || {})["design"] || {})["hide_shipping_selector_when_single"] != false
        }
      rescue StandardError => e
        Rails.logger.warn("[CodForm::MetafieldSyncService] early pricing skipped shop_id=#{shop.id} #{e.class}")
        nil
      end

      # PRE-3 (I.6): true when the checkout payment function should hide COD.
      # Only while the form is actually live — never hide COD at checkout for a shop whose form is off.
      def hide_cod_at_checkout?(shop)
        config = CodForm::ShopConfig.find_by(shop_id: shop.id)
        return false if config.nil? || !config.cod_form_mode?
        return false unless config.general.is_a?(Hash) && config.general["cod_only_through_form"] == true

        # At the monthly order limit the COD button is off: COD must come back at checkout.
        return false if cap_state(shop) == "fallback"

        CodForm::Availability.call(shop)[:available] == true
      rescue StandardError
        false
      end

      # ---- pure -------------------------------------------------------------------------------

      # facts (string keys):
      #   "available"        CodForm::Availability.call(shop)[:available]
      #   "mode_off"         Availability's `mode_off`: everything is on except storefront_mode
      #   "has_preview_token"
      #   "api_host"         ENV["APP_HOST"]
      #   "shop_domain", "version"
      #   "general"          cod_form_shop_configs.general
      #   "button"           {"preset", "config"}
      #   "rules"            CodForm::RulesAdapter.from_setting(setting)
      #   "quantity_offers"  active quantity offers (C.4 wrappers)
      #   "active_offer_types"  offer types with at least one offer active now
      #   "gates"            CodForm::Gates.for(shop)
      #   "cap_state"        "ok" | "grace" | "flagged" | "fallback"
      #   "otp_enabled", "partial_enabled", "has_pixels"
      #   "published_forms"  [published_config, ...] of active forms
      #   "shop_country"
      # => the input of CodForm::Engine::MetafieldPayload.build (E.13)
      def build_input(facts)
        gates = obj(facts["gates"])
        general = gated_general(obj(facts["general"]), gates)
        button = obj(facts["button"])
        preset = button["preset"].to_s
        preset = "B" if preset.empty? || (preset == "A" && !allowed?(gates, "preset_a"))
        offers = allowed?(gates, "quantity_offers") ? Array(facts["quantity_offers"]) : []
        live = facts["available"] == true
        # C.1.2 `test_only`: the merchant is testing before going live. The embed then renders
        # only with ?codk_preview=<token>; the token itself is checked server-side at session.
        test_only = !live && facts["mode_off"] == true && facts["has_preview_token"] == true

        {
          "enabled" => live || test_only,
          "api" => api_base(facts["api_host"]),
          "shop" => facts["shop_domain"].to_s,
          "version" => facts["version"].to_i,
          "general" => general,
          "button" => { "preset" => preset, "config" => obj(button["config"]) },
          "rules" => obj(facts["rules"]),
          "quantity_offers" => offers,
          "features" => features(facts.merge("general" => general, "quantity_offers" => offers, "preset" => preset)),
          "cap_fallback" => facts["cap_state"] == "fallback",
          "test_only" => test_only
        }.tap do |out|
          bundles = allowed?(gates, "quantity_offers") ? Array(facts["bundles"]) : []
          out["bundles"] = bundles if bundles.any?
        end
      end

      # Optional chunks the loader may prefetch (C.1.2 `features`), in a stable order.
      def features(facts)
        gates = obj(facts["gates"])
        general = obj(facts["general"])
        types = Array(facts["active_offer_types"])
        forms = Array(facts["published_forms"]).select { |form| form.is_a?(Hash) }
        blocks = forms.flat_map { |form| Array(form["blocks"]) }.select { |block| block.is_a?(Hash) && block["enabled"] != false }
        fields = forms.flat_map { |form| Array(form["fields"]) }.select { |field| field.is_a?(Hash) && field["enabled"] != false }
        countries = Array(general["countries"])
        threshold = types.include?("threshold") && allowed?(gates, "threshold_offers")

        list = []
        list << "otp" if facts["otp_enabled"] == true
        list << "partial" if facts["partial_enabled"] == true
        list << "qty_offer" if Array(facts["quantity_offers"]).any?
        list << "bumps" if types.include?("bump") && allowed?(gates, "order_bumps")
        list << "downsell" if types.include?("downsell") && allowed?(gates, "downsell")
        list << "upsell" if types.include?("upsell") && allowed?(gates, "upsell")
        list << "discount" if general.dig("discounts", "code_field_enabled") == true
        list << "custom_fields" if allowed?(gates, "custom_fields") && fields.any? { |field| field["key"].to_s.start_with?("cf_") }
        list << "content" if blocks.any? { |block| CONTENT_BLOCK_TYPES.include?(block["type"]) }
        list << "india" if countries.include?("IN") || (countries.empty? && facts["shop_country"].to_s.upcase == "IN")
        list << "autocomplete" if general.dig("autocomplete", "enabled") == true
        list << "threshold" if threshold
        list << "pixels" if facts["has_pixels"] == true
        list << "embedded" if general.dig("embedded", "enabled") == true
        list << "preset_a" if facts["preset"] == "A"
        list << "theme_express" if forms.any? { |form| form.dig("design", "theme") == "express" }
        list << "pre_upsell" if types.include?("pre_upsell") && allowed?(gates, "order_bumps")
        list
      end

      # A gated-off feature is simply absent from the storefront config (J.1); the saved
      # configuration is kept in the database.
      def gated_general(general, gates)
        out = JSON.parse(JSON.generate(general))
        switch_off(out, %w[embedded enabled]) unless allowed?(gates, "embedded_mode")
        switch_off(out, %w[autocomplete enabled]) unless allowed?(gates, "address_autocomplete")
        switch_off(out, %w[discounts code_field_enabled]) unless allowed?(gates, "discount_code_field")
        switch_off(out, %w[rto gating_enabled]) unless allowed?(gates, "rto_gating")
        switch_off(out, %w[branding hide_powered_by]) unless allowed?(gates, "branding_removal")
        out["otp"]["mode"] = "before_order" if out["otp"].is_a?(Hash) && out["otp"]["mode"] == "risk_based" && !allowed?(gates, "risk_based_otp")
        out
      end

      def api_base(host)
        value = host.to_s.strip.sub(%r{/+\z}, "")
        return "" if value.empty?

        value.match?(%r{\Ahttps?://}) ? value : "https://#{value}"
      end

      private

      def obj(value)
        value.is_a?(Hash) ? value : {}
      end

      def allowed?(gates, key)
        gate = gates[key]
        gate.is_a?(Hash) && gate["allowed"] == true
      end

      def switch_off(general, path)
        group = general[path[0]]
        group[path[1]] = false if group.is_a?(Hash) && group.key?(path[1])
      end

      # ---- Rails side -------------------------------------------------------------------------

      def facts_for(shop, config)
        setting = shop.setting
        gates = CodForm::Gates.for(shop, config: config)
        button = CodForm::ButtonConfig.for(shop)
        active_offers = CodForm::Offer.where(shop_id: shop.id).active_now
        availability = CodForm::Availability.call(shop, config: config)
        {
          "available" => availability[:available] == true,
          "mode_off" => availability[:mode_off] == true,
          "has_preview_token" => config.preview_token.present?,
          "api_host" => ENV.fetch("APP_HOST", nil),
          "shop_domain" => shop.shopify_domain,
          "version" => config.config_version,
          "general" => CodFormAdmin::Validators::General.complete(config.general, engine_default(:general)),
          "button" => { "preset" => button.preset, "config" => button.config },
          "rules" => setting.present? ? CodForm::RulesAdapter.from_setting(setting) : {},
          "quantity_offers" => active_offers.of_type("quantity").ordered.map(&:to_engine_hash),
          "bundles" => active_offers.of_type("bundle").ordered.map(&:to_engine_hash),
          "active_offer_types" => active_offers.distinct.pluck(:offer_type),
          "gates" => gates,
          "cap_state" => cap_state(shop),
          "otp_enabled" => CodForm::OtpService.on?(setting, config.general),
          "partial_enabled" => CodForm::PartialRulesAdapter::ENABLED && setting.present? && setting.partial_payment_enabled == true,
          "has_pixels" => CodForm::TrackingPixel.where(shop_id: shop.id, enabled: true).exists? ||
            (setting.present? && setting.pixel_id.present?),
          "published_forms" => CodForm::Form.where(shop_id: shop.id).active.pluck(:published_config),
          "shop_country" => shop.country_code
        }
      end

      def engine_default(name)
        CodForm::Engine::Defaults.public_send(name)
      rescue StandardError
        nil
      end

      def cap_state(shop)
        state = CodForm::CapService.state(shop)
        state.is_a?(Hash) ? (state["state"] || state[:state]) : nil
      rescue StandardError => e
        Rails.logger.warn("[CodForm::MetafieldSyncService] cap state unavailable shop_id=#{shop.id} #{e.class}")
        nil
      end

      def write(shop, payload)
        shop.init_session
        owner_id = "gid://shopify/Shop/#{ShopifyAPI::Shop.current.id}"
        result = ShopifyServices::MetafieldsSetService.call(
          shop,
          [{ ownerId: owner_id, namespace: NAMESPACE, key: KEY, value: payload.to_json, type: "json" }]
        )
        ok = result.is_a?(Hash) && result[:metafields].present? && result[:user_errors].blank?
        Rails.logger.warn("[CodForm::MetafieldSyncService] metafield not written shop_id=#{shop.id}") unless ok
        ok
      rescue StandardError => e
        Rails.logger.warn("[CodForm::MetafieldSyncService] shop_id=#{shop.id} #{e.class}")
        false
      end

      # PRE-3: re-push the payment function configuration when the effective `hideCodAtCheckout`
      # value changed since the last push (kept in setup_state["hide_cod_at_checkout"]).
      def sync_payment_function(shop, config)
        wanted = hide_cod_at_checkout?(shop)
        state = config.setup_state.is_a?(Hash) ? config.setup_state : {}
        return if (state["hide_cod_at_checkout"] == true) == wanted

        setting = shop.setting
        return if setting.blank? || setting.payment_customization_id.blank?

        name = setting.payment_method_name.presence || "Cash on Delivery"
        return if ShopifyServices::PaymentCustomizationService.call(shop, name).blank?

        config.update_columns(setup_state: state.merge("hide_cod_at_checkout" => wanted), updated_at: Time.current)
      rescue StandardError => e
        Rails.logger.warn("[CodForm::MetafieldSyncService] payment function sync failed shop_id=#{shop.id} #{e.class}")
      end
    end
  end
end
