# frozen_string_literal: true

module Whatsapp
  # Which COD King default-number MSG91 templates each customer notification sends, mirroring the
  # template choice in the NetworkServices::Whatsapp* senders (keep in sync when those change).
  #
  # `in_use_names` is the set worth translating: the code/ENV defaults plus every template name set
  # by a shop that sends WhatsApp from the default number.
  module DefaultTemplates
    module_function

    # event key => setting column overriding the default names (nil: no per-shop override)
    EVENTS = {
      "order_confirmation" => :whatsapp_order_confirmation_template,
      "fulfilment" => :whatsapp_fulfilment_template,
      "abandoned_cart" => :whatsapp_abandoned_cart_template,
      "abandoned_cart_discount" => :whatsapp_abandoned_cart_template,
      "cod_verification" => :whatsapp_cod_verification_template,
      "first_purchase" => :whatsapp_first_purchase_template,
      "pre_verify_otp" => :whatsapp_pre_verify_otp_template,
      "prepaid" => :whatsapp_prepaid_template_name
    }.freeze

    # Events with a merchant-facing preview (customer notifications page and onboarding).
    PREVIEW_EVENTS = %w[order_confirmation fulfilment abandoned_cart abandoned_cart_discount cod_verification first_purchase].freeze

    # Setting flags that mean a shop sends WhatsApp at all.
    WHATSAPP_FLAGS = %i[whatsapp confirmation_whatsapp fulfilment_whatsapp ac_whatsapp
                        send_verification_link_only first_purchase_whatsapp_enabled].freeze

    def default_names(event)
      case event.to_s
      when "order_confirmation" then ["order_confirmation"]
      when "fulfilment" then %w[order_fulfilment order_fulfilment_with_tracking_number]
      when "abandoned_cart"
        [
          ENV.fetch("WHATSAPP_AC_TEMPLATE_WITH_IMAGE", nil).presence || "ac5_with_image",
          ENV.fetch("WHATSAPP_AC_TEMPLATE_WITHOUT_IMAGE", nil).presence || "ac4_without_image"
        ]
      when "abandoned_cart_discount"
        [
          # Discount reminders on the default number use the _ALT image template.
          ENV.fetch("WHATSAPP_AC_DISCOUNT_TEMPLATE_WITH_IMAGE_ALT", nil).presence || "ac_with_discount_with_image2",
          ENV.fetch("WHATSAPP_AC_DISCOUNT_TEMPLATE_WITHOUT_IMAGE", nil).presence || "ac_with_discount"
        ]
      when "cod_verification" then ["cod_verification_link5"]
      when "first_purchase" then ["first_purchase"]
      when "pre_verify_otp" then ["pre_verify_otp1", ENV.fetch("MSG91_TEMPLATE_NAME", nil).presence || "pre_verify_otp"]
      when "prepaid" then ["order_tracking_new", *Whatsapp::PrepaidTemplateLibrary.all.map { |e| e[:msg91_template_name] }]
      else []
      end.uniq
    end

    # The order confirmation setting may carry a variable list: "name:var$var".
    def template_name_from_config(value)
      value.to_s.split(":", 2).first.to_s.strip.presence
    end

    def default_number?(setting)
      setting.respond_to?(:branded_whatsapp_number) && setting.branded_whatsapp_number.blank?
    end

    # Template names this shop's notification would send (its override, else the defaults).
    def names_for(setting, event)
      column = EVENTS[event.to_s]
      override = column && setting.respond_to?(column) ? template_name_from_config(setting.public_send(column)) : nil
      override ? [override] : default_names(event)
    end

    # { "order_confirmation" => ["order_confirmation"], ... } for one shop.
    def for_shop(shop)
      setting = shop.setting
      return {} unless setting

      EVENTS.keys.index_with { |event| names_for(setting, event) }
    end

    # Every template name worth translating, sorted.
    def in_use_names
      names = EVENTS.keys.flat_map { |event| default_names(event) }

      flags = WHATSAPP_FLAGS.select { |flag| Setting.column_names.include?(flag.to_s) }
      scope = Setting.where(branded_whatsapp_number: [nil, ""])
      scope = scope.where(flags.map { |flag| "settings.#{flag} = TRUE" }.join(" OR ")) if flags.any?
      EVENTS.each_value do |column|
        next unless Setting.column_names.include?(column.to_s)

        scope.where.not(column => [nil, ""]).distinct.pluck(column).each do |value|
          name = template_name_from_config(value)
          names << name if name
        end
      end

      names.compact.uniq.sort
    end
  end
end
