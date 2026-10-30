# frozen_string_literal: true

module Whatsapp
  module Inbox
    module ReplyVariables
      KEYS = WhatsappInboxSetting::VARIABLES
      PATTERN = /\{\{\s*([a-z_]+)\s*\}\}/

      module_function

      def values_for(conversation)
        shop = conversation.shop
        order = latest_order(shop, conversation.phone_last10)
        name = conversation.customer_name.to_s.squish.presence || order&.customer_name.to_s.squish
        {
          'name' => name.to_s,
          'first_name' => name.to_s.split(' ').first.to_s,
          'order_number' => order_number(order),
          'order_status' => order ? OrderLookup.status_label(order).to_s : '',
          'tracking_url' => order&.order_status_url.to_s,
          'order_amount' => order_amount(order),
          'store_name' => store_name(conversation, shop)
        }
      end

      def render(conversation, text, values = nil)
        text = text.to_s
        return text.strip unless PATTERN.match?(text)

        values ||= values_for(conversation)
        text.gsub(PATTERN) { values.fetch(Regexp.last_match(1), '').to_s }
            .gsub(/[ \t]+([,.!?])/, '\1')
            .gsub(/[ \t]{2,}/, ' ')
            .gsub(/^[ \t]+|[ \t]+$/, '')
            .strip
      end

      def latest_order(shop, phone_last10)
        return nil if shop.nil? || phone_last10.blank?

        OrderLookup.latest(shop, phone_last10)
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::ReplyVariables] order lookup failed shop=#{shop&.id}: #{e.class}: #{e.message}")
        nil
      end

      def order_number(order)
        number = order&.order_number.to_s.strip
        return '' if number.blank?

        number.start_with?('#') ? number : "##{number}"
      end

      def order_amount(order)
        amount = order&.order_amount.to_s.strip
        return '' if amount.blank?

        [order.currency.to_s.strip.presence, amount].compact.join(' ')
      end

      def store_name(conversation, shop)
        conversation.whatsapp_account&.verified_name.to_s.strip.presence ||
          shop&.shopify_domain.to_s.delete_suffix('.myshopify.com').tr('-', ' ').split.map(&:capitalize).join(' ')
      end
    end
  end
end
