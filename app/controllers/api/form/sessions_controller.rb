# frozen_string_literal: true

module Api
  module Form
    # POST /api/form/session (D.1): opens a form session in one round trip (NFR-3).
    # No token. A fallback is a 200 with `ok: true`, `fallback: <code>` and no token.
    class SessionsController < BaseController
      RTL_LANGUAGES = %w[ar ur he fa].freeze
      SOURCES = CodForm::Session::SOURCES
      DEVICES = CodForm::Session::DEVICES
      ATTRIBUTION_EXTRA_KEYS = %w[ttclid sccid epik].freeze
      TRACKING_KEYS = %w[fbp fbc ttp ttclid ga_client_id ga_session_id scid sccid epik].freeze

      skip_before_action :authenticate_session!
      # Availability problems are fallbacks here, not errors (A.3).
      skip_before_action :check_module!

      def create
        availability = CodForm::Availability.call(shop, config: shop_config)
        is_test = shop_config.preview_token_matches?(body["preview_token"])
        unless CodForm::Availability.usable?(availability, test: is_test)
          return render_fallback(availability[:fallback] == "kill_switch" ? "kill_switch" : "module_disabled")
        end

        cap = is_test ? { "state" => "ok" } : CodForm::CapService.state(shop)
        return render_fallback("cap_reached", cap: cap) if cap["state"] == "fallback"

        general = CodForm::QuoteService.general_settings(shop_config)
        fraud = CodForm::QuoteService.fraud_settings(shop_config)
        flags = CodForm::Gates.flags(shop, config: shop_config)
        setting = shop.setting

        recovery = recovery_prefill
        country = buyer_country(general, recovery)
        return render_fallback("not_eligible_country") if country.nil?

        items = recovery ? Array(recovery["items"]) : body["items"]
        begin
          lines = CodForm::CatalogService.lines(shop, items, country: country)
        rescue CodForm::Errors::InvalidItem
          return render_fallback("config_error")
        end
        return render_fallback("bundle_cart") if bundle_cart?(lines)
        CodForm::QuoteService.remember_automatic_discounts(shop) if discounted_cart?(lines)

        form = pick_form(lines, is_test)
        return render_fallback("config_error") if form.nil? || !form.published_config.is_a?(Hash) || form.published_config.empty?

        locale = CodForm::Engine::FormConfig.storefront_locale(form.published_config, clean_locale(body["locale"]), general["language"])
        session = create_session(form, lines, country, locale, is_test, recovery)
        built = CodForm::QuoteService.build(
          shop: shop, config: shop_config, session: session,
          params: { "address" => { "country" => country } }, stage: "page", ip: request.remote_ip.to_s
        )
        session.update_columns(ab_assignments: built.offers.ab_assignments) if built.offers.ab_assignments.present?
        remember_asset_base

        token = CodForm::Engine::SessionToken.issue(
          secret: self.class.token_secret, shop_id: shop.id, session_id: session.public_id,
          issued_at: session.created_at.to_i, ttl_seconds: CodForm::Session::TOKEN_TTL.to_i, test: is_test
        )
        after_open(session, recovery)

        render_ok(
          "token" => token,
          "session_id" => session.public_id,
          "expires_at" => session.expires_at.utc.iso8601,
          "config_version" => shop_config.config_version,
          "fallback" => nil,
          "test" => is_test,
          "cap" => { "state" => cap["state"] },
          "locale" => locale,
          "rtl" => RTL_LANGUAGES.include?(locale.split("-").first),
          "form" => {
            "id" => form.id, "version" => form.published_version,
            "config" => CodForm::Engine::FormConfig.for_storefront(form.published_config, locale: locale)
          },
          "countries" => countries_for(general, country),
          "country_schema" => built.schema,
          "otp" => CodForm::OtpService.settings(setting, built.general, form.published_config),
          "offers" => offers_payload(built, flags),
          "features" => features(form, general, flags),
          "autocomplete" => autocomplete_payload(general, flags),
          "pixels" => pixels_for(lines),
          "event_ids" => { "initiate_checkout" => "codkf_#{session.public_id}_ic" },
          "handoff" => handoff_payload(setting, form, general),
          "drawer" => drawer_payload(setting),
          "security" => {
            "min_submit_ms" => (fraud["min_submit_seconds"].to_f * 1000).round,
            "honeypot" => fraud["honeypot"] == false ? nil : HONEYPOT_FIELD
          },
          "prefill" => recovery,
          "ab" => session.ab_assignments.is_a?(Hash) ? session.ab_assignments : {},
          "quote" => built.public_quote
        )
      end

      private

      # The theme cart drawer under the popup form: same popup condition as the legacy widget.
      def drawer_payload(setting)
        return { "strategy" => 0, "selectors" => "" } if setting.nil?

        {
          "strategy" => setting.pre_v2_overwrite_popup_condition.to_i,
          "selectors" => setting.pre_v2_cart_drawer_layout_selectors.to_s
        }
      end

      def render_fallback(code, cap: nil)
        payload = { "fallback" => code, "token" => nil }
        payload["cap"] = { "state" => cap["state"] } if cap
        render_ok(payload)
      end

      # ABN-2: a recovery link opens a new session prefilled from the abandoned one.
      def recovery_prefill
        token = body["recovery_token"].to_s
        return nil unless token.match?(/\A[A-Za-z0-9_\-]{16,64}\z/)

        prefill = CodForm::Abandonment::RecoveryService.prefill(shop, token)
        return nil unless prefill.is_a?(Hash) && Array(prefill["items"]).any?

        @recovered_from = prefill["recovered_from"].to_s
        prefill.except("recovered_from")
      rescue StandardError => e
        Rails.logger.warn("[Api::Form::Sessions] recovery prefill failed shop_id=#{shop.id} #{e.class}")
        nil
      end

      # VIS-3. nil = the buyer's country is not enabled for the form.
      def buyer_country(general, recovery)
        country = (recovery && recovery.dig("address", "country")).to_s.strip.upcase
        country = body["country"].to_s.strip.upcase unless country.match?(/\A[A-Z]{2}\z/)
        country = shop.country_code.to_s.strip.upcase unless country.match?(/\A[A-Z]{2}\z/)
        enabled = Array(general["countries"]).map { |c| c.to_s.upcase }
        return nil unless country.match?(/\A[A-Z]{2}\z/)
        return nil unless enabled.empty? || enabled.include?(country)

        country
      end

      # OFF-9 / decision 12: a cart line priced below the catalog price by a cart transform
      # (bundle apps) cannot be reproduced by a draft order. The client price is used for this
      # comparison only, never as a price.
      def bundle_cart?(lines)
        Array(body["items"]).each_with_index.any? do |item, index|
          next false unless item.is_a?(Hash) && item["properties"].is_a?(Hash)
          next false unless item["properties"].keys.any? { |key| key.to_s.start_with?("_") }

          cart_price = item["cart_line_price_cents"]
          line = lines[index]
          cart_price.is_a?(Numeric) && line && cart_price < line["unit_price_cents"].to_i * line["quantity"].to_i
        end
      end

      # A storefront cart line cheaper than its catalog price: the store has discounts running, so
      # the opening quote asks Shopify for them. Only a hint to spend that call; never a price.
      def discounted_cart?(lines)
        Array(body["items"]).each_with_index.any? do |item, index|
          next false unless item.is_a?(Hash)

          cart_price = item["cart_line_price_cents"]
          line = lines[index]
          cart_price.is_a?(Numeric) && line && cart_price < line["unit_price_cents"].to_i * line["quantity"].to_i
        end
      end

      def pick_form(lines, is_test)
        forms = CodForm::Form.where(shop_id: shop.id).active.ordered.to_a
        forms = [CodForm::Form.default_for(shop)] if forms.empty?
        picked = CodForm::Engine::FormTargeting.pick(
          forms: forms.map { |f| { "id" => f.id, "is_default" => f.is_default, "status" => f.status, "position" => f.position, "targeting" => f.targeting } },
          cart: { "lines" => lines }, requested_id: body["form_id"], is_test: is_test
        )
        picked && forms.find { |f| f.id == picked["id"] }
      end

      def clean_locale(value)
        locale = value.to_s.strip.tr("_", "-")
        locale.match?(/\A[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?\z/) ? locale.downcase[0, 12] : "en"
      end

      def create_session(form, lines, country, locale, is_test, recovery)
        source = recovery ? "recovery" : body["source"].to_s
        tracking = hash(body["tracking"]).slice(*TRACKING_KEYS).transform_values { |v| v.to_s[0, 500] }
        tracking["page_url"] = body["page_url"].to_s[0, 1000]
        tracking["consent"] = hash(body["consent"]).slice("analytics", "marketing", "sale_of_data").transform_values { |v| v == true }
        tracking["recovered_from"] = @recovered_from if @recovered_from.present?

        attrs = {
          shop_id: shop.id, cod_form_id: form.id, form_version: form.published_version,
          status: CodForm::Session::STATUS_OPEN,
          source: SOURCES.include?(source) ? source : "product",
          is_test: is_test, country_code: country,
          currency: lines.first["currency"].to_s.presence || body["currency"].to_s.upcase[0, 3].presence,
          locale: locale, device: DEVICES.include?(body["device"].to_s) ? body["device"].to_s : nil,
          ip: request.remote_ip.to_s, user_agent: request.user_agent.to_s[0, 500],
          client_id: body["client_id"].to_s.gsub(/[^A-Za-z0-9_\-.]/, "")[0, 64].presence,
          cart_snapshot: { "items" => lines.map { |l| l.slice("variant_id", "quantity", "properties") }, "source" => source },
          attribution: attribution, tracking: tracking,
          ab_assignments: hash(body["ab"]).first(20).to_h.transform_keys(&:to_s).transform_values { |v| v.to_s[0, 32] },
          address: { "country" => country }
        }
        if recovery
          attrs[:address] = hash(recovery["address"]).merge("country" => country)
          attrs[:contact] = hash(recovery["contact"]).slice("email", "first_name", "last_name")
        end
        CodForm::Session.create!(attrs)
      end

      def attribution
        raw = hash(body["attribution"])
        normalized = CampaignAttributionHelper.normalize(raw)
        ATTRIBUTION_EXTRA_KEYS.each do |key|
          value = raw[key].to_s.strip
          normalized[key] = value[0, 500] unless value.empty? || normalized.key?(key)
        end
        normalized
      end

      # The storefront reports where the extension assets are served from; only Shopify's CDN
      # path of our own extension is accepted (B.1 asset_base).
      def remember_asset_base
        base = CodFormAdmin::PreviewFramesController.safe_asset_base(body["assets_base"], ENV["COD_FORM_EXTENSION_UUID"])
        return if base.nil? || base == shop_config.asset_base

        shop_config.update_columns(asset_base: base)
      end

      def after_open(session, recovery)
        CodForm::FunnelLogger.log(
          shop_id: shop.id, session_token: session.public_id, type: "cf_form_open",
          meta: CodForm::QuoteService.funnel_meta(session).merge(
            "product_ids" => Array(session.quote_snapshot["lines"]).map { |l| l["product_id"] }.uniq.first(20),
            "utm_campaign" => session.attribution["utm_campaign"]
          ).compact
        )
        if recovery
          CodForm::FunnelLogger.log(shop_id: shop.id, session_token: session.public_id, type: "cf_recovery_open",
                                    meta: CodForm::QuoteService.funnel_meta(session))
        end
        CodForm::Tracking::ServerDispatchJob.perform_async(session.id, "initiate_checkout")
      rescue StandardError => e
        Rails.logger.warn("[Api::Form::Sessions] after_open failed shop_id=#{shop.id} #{e.class}")
      end

      def countries_for(general, country)
        CodForm::CatalogService.countries_for(general, country)
      end

      def offers_payload(built, flags)
        offers = built.offers.offers
        quantity = built.lines.filter_map { |line| CodForm::Engine::Offers.match_quantity_offer(offers: offers["quantity"], line: line) }.first
        catalog = built.offers.bump_catalog
        {
          "quantity" => quantity && quantity.slice("id", "config"),
          "bumps" => Array(offers["bumps"]).filter_map do |offer|
            bump_config = offer["config"].is_a?(Hash) ? offer["config"] : {}
            variant = bump_config["kind"].to_s == "variant" ? catalog[bump_config["variant_id"].to_s] : nil
            next if bump_config["kind"].to_s == "variant" && (variant.nil? || variant["available"] == false)

            price = bump_config["price_cents"].is_a?(Numeric) ? bump_config["price_cents"].to_i : variant && variant["unit_price_cents"]
            { "id" => offer["id"], "config" => bump_config, "unit_price_cents" => price.to_i }
          end,
          "downsell" => offers["downsell"] && offers["downsell"]["id"].is_a?(Integer) ? offers["downsell"].slice("id", "config") : nil,
          "thresholds" => Array(offers["thresholds"]).map { |offer| offer.slice("id", "config") },
          # The pre-purchase upsell rules this cart's products match, with their products priced; the
          # quote's "pre_upsell" says which one (if any) the popup shows for the cart as it is.
          # Bundles with a product in the cart that the form shows (complete sets get their
          # discount from the quote, whatever is shown here).
          "bundles" => Array(offers["bundles"]).filter_map do |offer|
            next if offer.dig("config", "show_in_form") == false

            CodForm::Engine::Bundles.public_bundle(offer: offer, catalog: catalog)
          end,
          "pre_upsells" => Array(offers["pre_upsells"]).filter_map do |offer|
            rule = CodForm::Engine::PreUpsells.public_offer(offer: offer, catalog: catalog, lines: built.lines)
            rule["products"].any? ? rule : nil
          end,
          "upsell_enabled" => flags["upsell"] == true && !built.offers.upsell.nil?
        }
      end

      def features(form, general, flags)
        out = {
          "discount_code" => flags["discount_code_field"] == true && general.dig("discounts", "code_field_enabled") == true,
          "custom_fields" => flags["custom_fields"] == true,
          "autocomplete" => autocomplete?(general, flags),
          "pay_online" => pay_online?(form, general),
          "hide_branding" => flags["branding_removal"] == true && general.dig("branding", "hide_powered_by") == true,
          # G.8: the same switch the server-side dispatcher reads; false = fire pixels without
          # waiting for the Customer Privacy consent.
          "respect_consent" => general.dig("consent", "respect_customer_privacy") != false
        }
        out["pay_online_handler"] = true if rabbitpay_handler?
        out
      end

      # Address suggestions come from the merchant's own key: Google Places or Ola Maps Places.
      def autocomplete_provider(general)
        general.dig("autocomplete", "provider").to_s == "ola" ? "ola" : "google"
      end

      def autocomplete_key(general)
        general.dig("autocomplete", "#{autocomplete_provider(general)}_api_key").to_s.strip
      end

      # Only the key of the chosen provider is sent to the storefront.
      def autocomplete_payload(general, flags)
        on = autocomplete?(general, flags)
        provider = autocomplete_provider(general)
        { "provider" => provider, "google_api_key" => on && provider == "google" ? autocomplete_key(general) : "",
          "ola_api_key" => on && provider == "ola" ? autocomplete_key(general) : "" }
      end

      def autocomplete?(general, flags)
        flags["address_autocomplete"] == true && general.dig("autocomplete", "enabled") == true &&
          autocomplete_key(general) != ""
      end

      def pay_online?(form, general)
        form.published_config.dig("pay_online", "enabled") != false && general.dig("prepaid", "show_pay_online") != false
      end

      def rabbitpay_handler?
        row = CodForm::Integration.where(shop_id: shop.id, provider: "rabbitpay").first
        row.present? && row.config.is_a?(Hash) && row.config["enabled"] == true
      rescue StandardError
        false
      end

      # Storefront representation only (C.6): PixelResolver already drops tokens; the slice
      # below makes sure nothing else can ever leave through this response.
      def pixels_for(lines)
        pixels = CodForm::Tracking::PixelResolver.for(
          shop, product_ids: lines.map { |l| l["product_id"] }.uniq, collection_ids: lines.flat_map { |l| l["collection_ids"] }.uniq
        )
        Array(pixels).map do |pixel|
          pixel = pixel.deep_stringify_keys
          out = pixel.slice("platform", "pixel_id", "targeting")
          # tiktok_event decides the browser event name (PlaceAnOrder / CompletePayment): the server
          # sends the same name, so the browser must know it for the two to deduplicate (I.2).
          out["config"] = hash(pixel["config"]).slice("browser", "purchase_event", "events", "conversion_label", "tiktok_event")
          out
        end
      rescue StandardError => e
        Rails.logger.warn("[Api::Form::Sessions] pixels failed shop_id=#{shop.id} #{e.class}")
        []
      end

      # The Storefront API token is public by design; it is sent only when the partial step or
      # Pay online can occur for this shop.
      def handoff_payload(setting, form, general)
        partial = setting&.partial_payment_enabled == true
        needed = partial || pay_online?(form, general)
        {
          "storefront_token" => needed ? setting&.store_front_token.to_s.presence : nil,
          "dummy_variant_id" => partial ? setting&.partial_dummy_variant_id.to_s.presence : nil
        }
      end

      def hash(value)
        value.is_a?(Hash) ? value : {}
      end
    end
  end
end
