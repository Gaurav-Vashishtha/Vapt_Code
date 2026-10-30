# frozen_string_literal: true

module CodForm
  module Tracking
    # ARCHITECTURE.md I.2 — the one table of pixel event names and shared event ids.
    # Pure Ruby (no Rails): the browser chunks and the server clients must agree on these values.
    module EventMap
      PLATFORMS = %w[meta tiktok ga4 google_ads snapchat pinterest].freeze

      MOMENT_INITIATE_CHECKOUT = "initiate_checkout"
      MOMENT_PURCHASE = "purchase"
      MOMENTS = [MOMENT_INITIATE_CHECKOUT, MOMENT_PURCHASE].freeze

      PURCHASE_EVENTS = %w[purchase lead].freeze

      # Row key => platform => event name sent to the vendor's server API.
      # nil means "nothing is sent for this platform at this moment".
      SERVER_EVENTS = {
        "initiate_checkout" => {
          "meta" => "InitiateCheckout", "tiktok" => "InitiateCheckout", "ga4" => "begin_checkout",
          "google_ads" => nil, "snapchat" => "START_CHECKOUT", "pinterest" => "add_to_cart"
        },
        "purchase" => {
          "meta" => "Purchase", "tiktok" => "CompletePayment", "ga4" => "purchase",
          "google_ads" => "conversion", "snapchat" => "PURCHASE", "pinterest" => "checkout"
        },
        "lead" => {
          "meta" => "Lead", "tiktok" => "SubmitForm", "ga4" => "generate_lead",
          "google_ads" => "conversion", "snapchat" => "SIGN_UP", "pinterest" => "lead"
        }
      }.freeze

      # The browser tags use other spellings for a few events.
      BROWSER_OVERRIDES = {
        "pinterest" => { "add_to_cart" => "addtocart" }
      }.freeze

      # Field that carries the shared id in each vendor's browser call.
      BROWSER_DEDUP_FIELDS = {
        "meta" => "eventID", "tiktok" => "event_id", "ga4" => "transaction_id",
        "google_ads" => "transaction_id", "snapchat" => "client_dedup_id", "pinterest" => "event_id"
      }.freeze

      # C.6 config.events key that switches a moment on or off for one pixel.
      CONFIG_EVENT_KEYS = { "initiate_checkout" => "form_open", "purchase" => "purchase" }.freeze

      module_function

      def moment?(moment)
        MOMENTS.include?(moment.to_s)
      end

      # "initiate_checkout" | "purchase" | "lead"
      def row_key(moment, purchase_event = "purchase")
        return MOMENT_INITIATE_CHECKOUT if moment.to_s == MOMENT_INITIATE_CHECKOUT
        return nil unless moment.to_s == MOMENT_PURCHASE

        purchase_event.to_s == "lead" ? "lead" : "purchase"
      end

      # Event name for the vendor's server API, or nil when the platform gets nothing.
      # config is the pixel's C.6 config ("purchase_event", "tiktok_event").
      def event_name(platform:, moment:, config: nil)
        config = config.is_a?(Hash) ? config : {}
        key = row_key(moment, config["purchase_event"])
        return nil if key.nil?

        row = SERVER_EVENTS[key]
        name = row[platform.to_s]
        if platform.to_s == "tiktok" && key == "purchase" && config["tiktok_event"].to_s == "place_order"
          name = "PlaceAnOrder"
        end
        name
      end

      def browser_event_name(platform:, moment:, config: nil)
        name = event_name(platform: platform, moment: moment, config: config)
        return nil if name.nil?

        (BROWSER_OVERRIDES[platform.to_s] || {})[name] || name
      end

      # Shared event id (browser and server use the same string).
      #   form open            -> "codkf_<session_id>_ic"
      #   order, purchase      -> "order_<order_id>_purchase"   (F20)
      #   order, lead          -> "order_<order_id>_lead"
      def event_id(moment:, session_id: nil, order_id: nil, purchase_event: "purchase")
        case row_key(moment, purchase_event)
        when "initiate_checkout"
          return nil if session_id.to_s.empty?

          "codkf_#{session_id}_ic"
        when "purchase"
          order_id.to_s.empty? ? nil : "order_#{order_id}_purchase"
        when "lead"
          order_id.to_s.empty? ? nil : "order_#{order_id}_lead"
        end
      end

      # Is this moment switched on for the pixel? Missing keys mean "on".
      def moment_enabled?(config, moment)
        config = config.is_a?(Hash) ? config : {}
        events = config["events"].is_a?(Hash) ? config["events"] : {}
        key = CONFIG_EVENT_KEYS[moment.to_s]
        return false if key.nil?

        events[key] != false
      end

      def browser_dedup_field(platform)
        BROWSER_DEDUP_FIELDS[platform.to_s]
      end
    end
  end
end
