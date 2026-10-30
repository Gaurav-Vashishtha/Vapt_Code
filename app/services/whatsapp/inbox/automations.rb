# frozen_string_literal: true

module Whatsapp
  module Inbox
    module Automations
      module_function

      def on_inbound(message, conversation_created:)
        return nil if ENV['WHATSAPP_INBOX_DISABLED'].present?
        return nil unless message&.inbound? && message.shop_id

        shop = Shop.find_by(id: message.shop_id)
        return nil unless shop

        setting = WhatsappInboxSetting.for(shop)
        safely('auto_label', message) { AutoLabeler.call(message) } if setting.auto_label
        safely('auto_reply', message) { route_reply(message, shop, setting, conversation_created) }
        nil
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::Automations] message=#{message&.id} #{e.class}: #{e.message}")
        nil
      end

      def route_reply(message, shop, setting, conversation_created)
        if ai_takes_over?(message, shop, setting)
          ::Whatsapp::Ai::ReplyJob.perform_in(::Whatsapp::Ai::ReplyJob::DEBOUNCE.to_i, message.id, conversation_created)
        elsif (minutes = ai_takeover_minutes(message, shop))
          ::Whatsapp::Ai::ReplyJob.perform_in(minutes * 60, message.id, false, true)
        else
          AutoReplyEngine.call(message, conversation_created: conversation_created, setting: setting)
        end
      end

      # Merchant keyword rules always win over the AI agent.
      def ai_takes_over?(message, shop, setting)
        ai_setting = WhatsappAiSetting.find_by(shop_id: shop.id)
        return false unless ai_setting&.active?
        return false if AutoReplyEngine.matching_rule(setting, message.body)

        conversation = WhatsappConversation.find_by(id: message.whatsapp_conversation_id, shop_id: shop.id)
        conversation.present? && ::Whatsapp::Ai::Responder.should_handle?(message, conversation, ai_setting)
      end

      def ai_takeover_minutes(message, shop)
        ai_setting = WhatsappAiSetting.find_by(shop_id: shop.id)
        minutes = ai_setting&.team_timeout_minutes.to_i
        return nil unless ai_setting&.active? && minutes.positive?

        conversation = WhatsappConversation.find_by(id: message.whatsapp_conversation_id, shop_id: shop.id)
        return nil unless conversation && ::Whatsapp::Ai::Responder.team_held?(message, conversation, ai_setting)
        return nil if ::Whatsapp::Ai::Responder.manually_paused?(conversation, Time.current)

        minutes
      end

      def safely(step, message)
        yield
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::Automations] #{step} failed message=#{message.id}: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
