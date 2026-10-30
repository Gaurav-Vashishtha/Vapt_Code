module Whatsapp
  module OptOutKeywordHandler
    # "cancel", "end", "remove" and "quit" are left out on purpose: in support
    # chats they almost always mean "cancel my order", not "unsubscribe".
    KEYWORDS = %w[stop unsubscribe stopp optout opt-out].freeze

    module_function

    def maybe_opt_out(shop:, from_phone:, text:)
      return if shop.nil? || text.blank? || from_phone.blank?
      norm = text.to_s.strip.downcase
      return unless KEYWORDS.include?(norm) || norm.start_with?('stop')

      phone = RtoOrder.normalize_phone(from_phone).to_s.gsub(/\D/, '')
      return if phone.blank?
      WhatsappOptOut.record!(shop_id: shop.id, phone_normalized: phone, reason: 'stop_keyword', source: 'inbound')
    rescue StandardError => e
      Rails.logger.warn("[Whatsapp::OptOutKeywordHandler] #{e.message}")
    end
  end
end
