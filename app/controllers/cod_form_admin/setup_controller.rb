# frozen_string_literal: true

module CodFormAdmin
  # Setup screen (D.15): mode switch, general settings (B.1.1), embed status, checklist, health,
  # test order, usage.
  class SetupController < BaseController
    def show
      render json: setup_payload
    end

    # PUT /cod_form/setup  {"general": {…partial B.1.1…}}
    def update
      raw = body_hash("general")
      invalid!("general", "is required") if raw.nil?

      old = Validators::General.complete(@config.general, engine_default(:general))
      general = validated!(Validators::General.normalize(raw, current: @config.general, engine_defaults: engine_default(:general)))
      Validators::General.gated_features(old, general).each { |feature| gate!(feature) }

      if general != @config.general
        @config.update!(general: general)
        audit_changes("general", old, general)
        bump!
      end
      render json: setup_payload
    end

    # POST /cod_form/mode  {"mode": "cod_form" | "legacy"}
    # Never blocked by a health item (PM Q3). Nothing on Setting is changed (DSH-5).
    def mode
      target = body["mode"].to_s
      invalid!("mode", "must be one of: #{CodForm::ShopConfig::STOREFRONT_MODES.join(', ')}") unless CodForm::ShopConfig::STOREFRONT_MODES.include?(target)

      old = @config.storefront_mode
      @config = target == CodForm::ShopConfig::STOREFRONT_MODE_COD_FORM ? CodForm::EnableService.call(@shop) : CodForm::EnableService.disable(@shop)
      audit("storefront_mode", old, @config.storefront_mode)
      render json: { "mode" => @config.storefront_mode, "enabled_at" => iso(@config.enabled_at) }
    end

    # POST /cod_form/setup/refresh_embed — re-reads the theme's settings_data.json.
    def refresh_embed
      CodForm::DomainSyncJob.perform_async(@shop.id)
      render json: { "embed" => embed_status(refresh: true) }
    end

    # POST /cod_form/setup/test_order — rotates the preview token (FRD-5).
    def test_order
      @config.rotate_preview_token!
      bump! # `test_only` in the metafield depends on the token being present
      audit("preview_token", "", "rotated")
      render json: { "preview_url" => preview_url }
    end

    # POST /cod_form/setup/dismiss_optin — the merchant closed the Summary opt-in card (DSH-9).
    # Stamps setup_state.dismissed_optin_at once; bootstrap then answers `optin_dismissed: true`.
    # Nothing the storefront reads changes, so there is no version bump.
    def dismiss_optin
      stamp_setup_state("dismissed_optin_at")
      render json: { "setup_state" => @config.setup_state.except("hide_cod_at_checkout") }
    end

    private

    def setup_payload
      embed = embed_status
      usage = usage_summary
      health = CodForm::SetupHealth.call(@shop, @config, embed: embed, cap: usage)
      {
        "mode" => @config.storefront_mode,
        "general" => Validators::General.complete(@config.general, engine_default(:general)),
        "setup_state" => @config.setup_state.except("hide_cod_at_checkout"),
        "checklist" => health["checklist"],
        "health" => health["health"],
        "embed" => embed,
        "preview_url" => preview_url,
        "usage" => usage
      }
    end

    def embed_status(refresh: false)
      status = CodForm::EmbedStatusService.call(@shop, refresh: refresh)
      stamp_setup_state("embed_seen_at") if status["enabled"] == true
      status
    end

    # nil until a preview token exists (created on first enable or by POST setup/test_order).
    def preview_url
      return nil if @config.preview_token.blank?

      # Always the .myshopify.com address: it never goes stale, and Shopify forwards it to the
      # store's current primary domain with the query string kept. The saved primary_domain is
      # only written at install, so a store that changed its domain later got a dead link.
      "https://#{@shop.shopify_domain}/?codk_preview=#{@config.preview_token}"
    end
  end
end
