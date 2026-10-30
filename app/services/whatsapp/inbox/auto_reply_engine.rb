# frozen_string_literal: true

module Whatsapp
  module Inbox
    module AutoReplyEngine
      SKIP_KINDS = %w[reaction system unsupported].freeze
      COOLDOWN = 6.hours
      AGENT_QUIET_PERIOD = 6.hours
      MAX_MESSAGE_AGE = 24.hours

      module_function

      def call(message, conversation_created:, setting: nil, now: Time.current)
        return nil unless eligible_message?(message, now)

        conversation = WhatsappConversation.find_by(id: message.whatsapp_conversation_id, shop_id: message.shop_id)
        return nil unless conversation&.window_open?(now)
        return nil if agent_replied_recently?(conversation, now)
        return nil if auto_replied_recently?(conversation, now)
        return nil unless conversation.whatsapp_account&.ready_to_send?

        setting ||= WhatsappInboxSetting.for(conversation.shop)
        template = pick_text(setting, message, conversation_created: conversation_created, now: now)
        return nil if template.blank?

        text = ReplyVariables.render(conversation, template)
        return nil if text.blank?

        previous = conversation.last_auto_reply_at
        return nil unless claim!(conversation, now)

        send_reply(conversation, text, now: now, previous: previous)
      end

      def pick_text(setting, message, conversation_created:, now:)
        rule = matching_rule(setting, message.body)
        return rule['reply_text'] if rule
        return setting.away_text if setting.away_enabled && BusinessHours.closed?(setting, now)
        return setting.welcome_text if setting.welcome_enabled && conversation_created

        nil
      end

      def matching_rule(setting, body)
        text = body.to_s
        return nil if text.blank?

        setting.enabled_keyword_rules.find do |rule|
          Array(rule['keywords']).any? { |keyword| keyword_match?(text, keyword, rule['match']) }
        end
      end

      def keyword_match?(text, keyword, match)
        keyword = keyword.to_s.squish
        return false if keyword.blank?

        if match == 'exact'
          normalize(text) == normalize(keyword)
        else
          pattern = Regexp.escape(keyword.downcase).gsub('\\ ', '\\s+')
          /(?<![[:alnum:]])#{pattern}(?![[:alnum:]])/i.match?(text)
        end
      end

      def normalize(text)
        text.to_s.downcase.squish.gsub(/[[:punct:][:space:]]+\z/, '')
      end

      def eligible_message?(message, now)
        return false unless message&.inbound? && message.shop_id
        return false if SKIP_KINDS.include?(message.kind.to_s)
        return false if message.occurred_at.nil? || message.occurred_at < now - MAX_MESSAGE_AGE
        return false if reserved_payload?(message)

        true
      end

      def reserved_payload?(message)
        payload = message.content.is_a?(Hash) ? message.content['payload'] : nil
        payload.present? && Whatsapp::EventRegistry.event_for_quick_reply_payload(payload).present?
      end

      def agent_replied_recently?(conversation, now)
        since = now - AGENT_QUIET_PERIOD
        return true if conversation.last_agent_reply_at && conversation.last_agent_reply_at > since

        WhatsappConversationMessage.where(whatsapp_conversation_id: conversation.id, source: 'agent')
                                   .where('occurred_at > ?', since)
                                   .exists?
      end

      def auto_replied_recently?(conversation, now)
        conversation.last_auto_reply_at.present? && conversation.last_auto_reply_at > now - COOLDOWN
      end

      def claim!(conversation, now)
        WhatsappConversation.where(id: conversation.id)
                            .where('last_auto_reply_at IS NULL OR last_auto_reply_at <= ?', now - COOLDOWN)
                            .update_all(last_auto_reply_at: now) == 1
      end

      # A reply rejected before reaching Meta frees the 6h slot; once Meta may have
      # accepted it, the slot stays taken so a retry never double-sends.
      def send_reply(conversation, text, now:, previous:)
        FreeformSender.call(conversation: conversation, agent: nil, source: 'auto_reply', text: text)
      rescue FreeformSender::WindowClosed, FreeformSender::NotReady, FreeformSender::Invalid => e
        release!(conversation, now, previous)
        log_failure(conversation, e)
      rescue StandardError => e
        log_failure(conversation, e)
      end

      def release!(conversation, now, previous)
        WhatsappConversation.where(id: conversation.id, last_auto_reply_at: now).update_all(last_auto_reply_at: previous)
      end

      def log_failure(conversation, error)
        Rails.logger.warn("[Whatsapp::Inbox::AutoReplyEngine] conversation=#{conversation.id} #{error.class}: #{error.message}")
        nil
      end
    end
  end
end
