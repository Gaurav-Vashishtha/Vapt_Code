# frozen_string_literal: true

module CodForm
  module Engine
    # Country-neutral defaults (ARCHITECTURE E.13, B.1.1, B.1.2, C.1, C.2, J.1, J.2).
    # Every method returns a fresh structure the caller may mutate.
    class Defaults
      LAUNCH_MARKETS = %w[HU CO RS DO MA PE PK EG].freeze
      RTL_LOCALES = %w[ar ur he fa].freeze

      class << self
        def form_config
          {
            "schema" => 1,
            "mode" => "popup",
            "design" => design,
            "blocks" => [
              { "id" => "order_summary", "type" => "order_summary", "enabled" => true,
                "settings" => { "show_image" => true, "show_compare_at" => true, "show_quantity" => true } },
              { "id" => "quantity_offer", "type" => "quantity_offer", "enabled" => true, "settings" => {} },
              { "id" => "contact", "type" => "fields", "enabled" => true, "settings" => { "group" => "contact", "title_key" => "contact_title" } },
              { "id" => "address", "type" => "fields", "enabled" => true, "settings" => { "group" => "address", "title_key" => "address_title" } },
              { "id" => "shipping", "type" => "shipping", "enabled" => true, "settings" => {} },
              { "id" => "bumps", "type" => "bumps", "enabled" => true, "settings" => {} },
              { "id" => "discount", "type" => "discount", "enabled" => false, "settings" => {} },
              { "id" => "totals", "type" => "totals", "enabled" => true, "settings" => { "show_tax_line" => false } },
              { "id" => "submit", "type" => "submit", "enabled" => true, "settings" => { "show_total_in_button" => true } }
            ],
            "fields" => [
              # One "Full name" field by default: first_name alone takes the whole name (it is split
              # into first / last name on the order). Switching last_name on asks for the two apart.
              { "key" => "first_name", "type" => "text", "group" => "contact", "enabled" => true, "required" => true, "width" => "full", "autocomplete" => "name", "validation" => { "max" => 60 } },
              { "key" => "last_name", "type" => "text", "group" => "contact", "enabled" => false, "required" => false, "width" => "half", "autocomplete" => "family-name", "validation" => { "max" => 60 } },
              { "key" => "phone", "type" => "tel", "group" => "contact", "enabled" => true, "required" => true, "width" => "full", "autocomplete" => "tel-national", "validation" => {} },
              { "key" => "email", "type" => "email", "group" => "contact", "enabled" => false, "required" => false, "width" => "full", "autocomplete" => "email", "validation" => {} },
              { "key" => "country", "type" => "country", "group" => "address", "enabled" => true, "required" => true, "width" => "full", "validation" => {} },
              { "key" => "address1", "type" => "text", "group" => "address", "enabled" => true, "required" => true, "width" => "full", "autocomplete" => "address-line1", "validation" => { "min" => 3, "max" => 120 } },
              { "key" => "address2", "type" => "text", "group" => "address", "enabled" => false, "required" => false, "width" => "full", "autocomplete" => "address-line2", "validation" => { "max" => 120 } },
              { "key" => "zip", "type" => "postal", "group" => "address", "enabled" => true, "required" => nil, "width" => "half", "autocomplete" => "postal-code", "validation" => {} },
              { "key" => "province", "type" => "province", "group" => "address", "enabled" => true, "required" => true, "width" => "half", "validation" => {} },
              { "key" => "city", "type" => "city", "group" => "address", "enabled" => false, "required" => true, "width" => "half", "validation" => { "max" => 80 } },
              { "key" => "gst_number", "type" => "text", "group" => "address", "enabled" => false, "required" => false, "width" => "full", "only_countries" => ["IN"], "validation" => { "regex" => "^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$" } },
              { "key" => "note", "type" => "textarea", "group" => "address", "enabled" => false, "required" => false, "width" => "full", "validation" => { "max" => 500 } },
              { "key" => "marketing_consent", "type" => "consent", "group" => "contact", "enabled" => false, "required" => false, "width" => "full", "default_checked" => false, "channels" => %w[sms email] }
            ],
            # Merchant overrides only (C.2): the default form has none. The fixed English defaults
            # ("Cash on Delivery", "Complete order — {total}") are the storefront package's own
            # texts (G.7, config/cod_form/default_texts.json). Seeding them here as `en` overrides
            # would put them ABOVE the translated defaults in the storefront merge order
            # (locale chunk < texts.en < texts[locale]) and show the English title and submit
            # button on every non-English storefront.
            "texts" => {},
            "thank_you" => {
              "type" => "order_status",
              "url" => "",
              "message" => { "en" => "Thank you {first_name}! Your order {order_name} is confirmed." },
              "whatsapp" => { "phone" => "", "message" => { "en" => "Hi, I just placed order {order_name}." } }
            },
            "steps" => { "phone_first" => false },
            "pay_online" => { "enabled" => true },
            "language" => ""
          }
        end

        def design
          {
            "primary" => "#111111", "on_primary" => "#ffffff", "text" => "#1a1a1a", "muted" => "#6b7280",
            "background" => "#ffffff", "surface" => "#f6f3ef", "border" => "#cccccc", "error" => "#d72c0d",
            "radius" => 4, "field_radius" => 5, "density" => "comfortable", "theme" => "classic",
            "header" => { "show_title" => true, "logo_url" => "", "show_close" => true },
            "sticky_submit" => true, "hide_shipping_selector_when_single" => true
          }
        end

        # The Express look (the COD King checkout widget's colours), as the designer's Express theme
        # sets it (FORM_THEMES.express in the admin).
        def express_design
          design.merge("theme" => "express", "primary" => "#000000", "on_primary" => "#ffffff", "text" => "#2f2f2f",
                       "muted" => "#7e7e7e", "background" => "#ffffff", "surface" => "#f6f8fc", "border" => "#e2e6ee",
                       "error" => "#e00000", "radius" => 12, "field_radius" => 4)
        end

        # Config of a form created from now on (a store's first form, a new blank form): the
        # Express theme. form_config stays the classic baseline the normaliser fills gaps from.
        def new_form_config
          form_config.merge("design" => express_design)
        end

        # cod_button_configs.config (preset B is the default preset).
        def button_config
          {
            "button" => {
              "labels" => { "default" => "Buy with COD" },
              "subtitles" => { "default" => "" },
              "style" => {
                "bg" => "#111111", "color" => "#ffffff", "border_color" => "#111111", "border_width" => 0, "radius" => 8,
                "shadow" => "md", "font_size" => 18, "bold" => true, "height" => 56, "full_width" => true,
                "icon" => "cart", "animation" => "none"
              },
              "placement" => { "position" => "below", "selector" => "" },
              "sticky" => { "enabled" => true, "labels" => { "default" => "Buy with COD" } },
              # The COD button starts on the product page only; the cart page and drawer are opt-in.
              "cart" => { "enabled" => false, "labels" => { "default" => "Checkout with COD" }, "selector" => "" },
              "drawer" => { "enabled" => false, "labels" => { "default" => "Checkout with COD" }, "selector" => "" },
              "quick_buy" => { "enabled" => false, "selector" => "" }
            },
            "theme" => {
              "rename_buy_now" => { "default" => "" },
              "rename_add_to_cart" => { "default" => "" },
              # The theme's Checkout button: on the cart page, and in the cart drawer.
              "rename_checkout" => { "default" => "" },
              "rename_drawer_checkout" => { "default" => "" },
              "hide" => { "add_to_cart" => false, "buy_now" => false, "checkout" => false, "drawer_checkout" => false,
                          "wallets" => false }
            },
            "quantity_widget" => { "enabled" => true, "position" => "above_buttons", "selector" => "" }
          }
        end

        def button_preset
          "B"
        end

        # cod_form_shop_configs.general (B.1.1)
        def general
          {
            "countries" => [],
            "pages" => { "product" => true, "cart" => true, "drawer" => true, "quick_buy" => false },
            "products" => { "scope" => "all", "include_product_ids" => [], "include_collection_ids" => [],
                            "exclude_product_ids" => [], "exclude_collection_ids" => [] },
            "order_total" => { "min_cents" => nil, "max_cents" => nil, "message" => "" },
            "hide_out_of_stock" => true,
            "cod_only_through_form" => false,
            "cod_fee_taxable" => false,
            "otp" => { "mode" => "before_order", "risk_band" => "medium", "whatsapp" => false, "max_attempts" => 3, "resend_wait_seconds" => 30 },
            "rto" => { "gating_enabled" => false, "block_band" => "high", "min_score" => nil, "message" => "" },
            "discounts" => { "code_field_enabled" => false, "codes_combine_with_offers" => false },
            "prepaid" => { "show_pay_online" => true, "discount_label_enabled" => false, "discount_label" => "" },
            "consent" => { "respect_customer_privacy" => true },
            "branding" => { "hide_powered_by" => false },
            "autocomplete" => { "enabled" => false, "provider" => "google", "google_api_key" => "", "ola_api_key" => "" },
            "abandonment" => { "enabled" => true, "delay_minutes" => 15, "create_draft_order" => false,
                               "recovery_discount" => { "type" => nil, "value" => 0 } },
            "embedded" => { "enabled" => false, "selector" => "", "position" => "after", "form_id" => nil },
            "upsell_window_minutes" => 5,
            # Setup → Form language: "" = follow the storefront language, else a locale code ("hi").
            "language" => ""
          }
        end

        # cod_form_shop_configs.fraud (B.1.2)
        def fraud
          {
            "blocked_message" => "",
            "limits" => {
              "phone" => { "enabled" => false, "max_orders" => 3, "window_hours" => 24 },
              "email" => { "enabled" => false, "max_orders" => 3, "window_hours" => 24 },
              "ip" => { "enabled" => false, "max_orders" => 5, "window_hours" => 24 }
            },
            "limit_message" => "",
            "max_quantity_per_order" => nil,
            "max_quantity_message" => "",
            "min_submit_seconds" => 3,
            "honeypot" => true
          }
        end

        # FRM-21: applying a template replaces "design" and the block order only.
        def templates
          order = %w[order_summary quantity_offer contact address shipping bumps discount totals submit]
          [
            { "key" => "classic", "name" => "Classic", "design" => design, "blocks_order" => order.dup },
            # The address form first, the totals under it (the common COD form look).
            { "key" => "address_first", "name" => "Address first", "design" => design,
              "blocks_order" => %w[contact address shipping quantity_offer bumps discount totals order_summary submit] },
            { "key" => "minimal", "name" => "Minimal",
              "design" => design.merge("primary" => "#1a1a1a", "surface" => "#ffffff", "border" => "#e3e3e3", "radius" => 4,
                                       "field_radius" => 4, "header" => { "show_title" => true, "logo_url" => "", "show_close" => true }),
              "blocks_order" => %w[contact address shipping order_summary quantity_offer bumps discount totals submit] },
            { "key" => "bold", "name" => "Bold",
              "design" => design.merge("primary" => "#e11d48", "on_primary" => "#ffffff", "surface" => "#fff1f2",
                                       "border" => "#fecdd3", "radius" => 16, "field_radius" => 12),
              "blocks_order" => %w[order_summary quantity_offer bumps contact address shipping discount totals submit] },
            { "key" => "compact", "name" => "Compact",
              "design" => design.merge("density" => "compact", "radius" => 8, "field_radius" => 6),
              "blocks_order" => %w[quantity_offer contact address shipping bumps discount order_summary totals submit] }
          ]
        end

        # feature_gates seed (J.1, product decision Q9). All rows enabled.
        def feature_gates
          {
            "free" => %w[cod_form_core quantity_offers block_lists velocity_limits basic_analytics first_pixel
                         abandonment_recovery discount_code_field custom_fields preset_a templates embedded_mode
                         order_bumps downsell upsell google_sheets extra_pixels pixels_p3],
            "pro" => %w[address_autocomplete threshold_offers multiple_forms advanced_analytics klaviyo_omnisend
                        risk_based_otp rto_gating branding_removal],
            "enterprise" => %w[ab_tests]
          }.flat_map do |tier, keys|
            keys.map { |key| { "feature_key" => key, "min_tier" => tier, "enabled" => true } }
          end
        end

        # plan_limits seed (J.2, product decision Q8). The country-group row carries the group definition
        # ("country_group") because its scope_key is the id of the seeded group row.
        def plan_limits
          [
            { "scope_type" => "plan", "scope_key" => "free", "plan_tier" => nil, "monthly_cap" => 60,
              "at_cap_behaviour" => "grace", "grace_orders" => 10, "overage_rate" => nil, "active" => true },
            { "scope_type" => "plan", "scope_key" => "pro", "plan_tier" => nil, "monthly_cap" => 500,
              "at_cap_behaviour" => "flag_only", "grace_orders" => nil, "overage_rate" => nil, "active" => true },
            { "scope_type" => "plan", "scope_key" => "enterprise", "plan_tier" => nil, "monthly_cap" => 10_000,
              "at_cap_behaviour" => "flag_only", "grace_orders" => nil, "overage_rate" => nil, "active" => true },
            { "scope_type" => "plan", "scope_key" => "enterprise_plus", "plan_tier" => nil, "monthly_cap" => nil,
              "at_cap_behaviour" => nil, "grace_orders" => nil, "overage_rate" => nil, "active" => true },
            { "scope_type" => "country_group", "scope_key" => nil, "plan_tier" => nil, "monthly_cap" => nil,
              "at_cap_behaviour" => nil, "grace_orders" => nil, "overage_rate" => nil, "active" => true,
              "country_group" => { "name" => "Launch markets", "country_codes" => LAUNCH_MARKETS.dup, "position" => 0 } }
          ]
        end

        # cod_form_global_settings seed
        def global_settings
          { "kill_switch" => false, "module_default_on" => false, "at_cap_behaviour" => "fallback", "grace_orders" => 0,
            "async_orders" => false, "usage_notice_thresholds" => [80, 100], "settings" => {} }
        end
      end
    end
  end
end
