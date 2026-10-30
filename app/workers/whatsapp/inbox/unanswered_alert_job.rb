# frozen_string_literal: true

module Whatsapp
  module Inbox
    class UnansweredAlertJob < ApplicationJob
      sidekiq_options queue: 'low', retry: 1

      MAX_AGE = 24.hours

      def perform
        now = Time.current
        WhatsappInboxSetting.where(unanswered_email_enabled: true).includes(:shop).find_each do |setting|
          alert_shop(setting, now)
        rescue StandardError => e
          Rails.logger.error("[Whatsapp::Inbox::UnansweredAlertJob] shop=#{setting.shop_id} #{e.class}: #{e.message}")
        end
      end

      private

      def alert_shop(setting, now)
        return if setting.shop.nil?
        return unless BusinessHours.open?(setting, now)

        waiting_since = now - setting.unanswered_email_minutes.minutes
        WhatsappConversation.where(shop_id: setting.shop_id, status: :open, unanswered_alert_sent_at: nil)
                            .where(last_inbound_at: (now - MAX_AGE)..waiting_since)
                            .where('last_agent_reply_at IS NULL OR last_agent_reply_at < last_inbound_at')
                            .find_each { |conversation| alert(conversation, now) }
      end

      def alert(conversation, now)
        claimed = WhatsappConversation.where(id: conversation.id, unanswered_alert_sent_at: nil)
                                      .update_all(unanswered_alert_sent_at: now) == 1
        WhatsappInboxMailer.unanswered(conversation.id).deliver_later if claimed
      end
    end
  end
end
