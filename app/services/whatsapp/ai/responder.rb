# frozen_string_literal: true

module Whatsapp
  module Ai
    module Responder
      class Error < StandardError; end
      class NotConfigured < Error; end
      class NoCredits < Error; end
      class RateLimited < Error; end

      SKIP_KINDS = %w[reaction system unsupported sticker].freeze
      AGENT_QUIET = 6.hours
      MAX_MESSAGE_AGE = 24.hours
      CONVERSATION_DAILY_CAP = 40
      TEST_DAILY_CAP = 100
      PLAYGROUND_DAILY_CAP = 50
      HANDOFF_PAUSE = 30.days
      HANDOFF_LABELS = {
        'cancel_request' => 'cancel_request',
        'return_refund' => 'return_refund',
        'address_change' => 'address_change',
        'payment_issue' => 'payment'
      }.freeze
      OPT_OUT_KEYWORDS = Whatsapp::OptOutKeywordHandler::KEYWORDS

      module_function

      def should_handle?(message, conversation, setting, now: Time.current, takeover: false)
        return false unless Config.enabled? && setting&.handles?(conversation)
        return false unless message_eligible?(message, now, max_age: takeover ? MAX_MESSAGE_AGE + 3.hours : MAX_MESSAGE_AGE)
        return takeover_ready?(message, conversation, setting, now) if takeover
        return false if paused?(conversation, now)
        return false if setting.agent_live? && !setting.reply_draft? && agent_replied_recently?(conversation, now)
        return false unless conversation.window_open?(now) && conversation.whatsapp_account&.ready_to_send?
        return true if setting.agent_test?

        Wallet.balance(conversation.shop).positive?
      end

      def team_held?(message, conversation, setting, now: Time.current)
        return false unless Config.enabled? && setting&.handles?(conversation) && message_eligible?(message, now)

        paused?(conversation, now) || (setting.agent_live? && agent_replied_recently?(conversation, now))
      end

      def takeover_ready?(message, conversation, setting, now)
        return false unless setting.team_timeout_minutes.to_i.positive?
        return false if manually_paused?(conversation, now)
        return false if WhatsappConversationMessage.where(whatsapp_conversation_id: conversation.id, source: 'agent')
                                                   .where('occurred_at > ?', message.occurred_at).exists?
        return false unless conversation.window_open?(now) && conversation.whatsapp_account&.ready_to_send?
        return true if setting.agent_test?

        Wallet.balance(conversation.shop).positive?
      end

      def manually_paused?(conversation, now)
        paused?(conversation, now) && conversation.ai_handoff_at.nil?
      end

      def on_inbound(message_id, conversation_created: false, now: Time.current, takeover: false)
        message = WhatsappConversationMessage.find_by(id: message_id)
        return nil unless message&.inbound?

        conversation = WhatsappConversation.find_by(id: message.whatsapp_conversation_id, shop_id: message.shop_id)
        return nil unless conversation

        shop = conversation.shop
        setting = WhatsappAiSetting.for(shop)
        return nil if newer_inbound?(conversation, message)
        return nil unless should_handle?(message, conversation, setting, now: now, takeover: takeover)
        if daily_cap_reached?(conversation, now, setting.daily_reply_limit)
          Rails.logger.warn("[Whatsapp::Ai::Responder] daily cap reached conv=#{conversation.id}")
          return limit_handoff!(conversation, setting, message, now)
        end
        return nil unless claim!(conversation, message)

        if takeover
          resume!(conversation)
          conversation.reload
          note = "The customer has been waiting about #{setting.team_timeout_minutes} minutes and the team has not replied. " \
                 'Apologise briefly for the wait, then help yourself. Only hand off again if you truly cannot help.'
        end

        mode = if setting.agent_test? then 'test'
               elsif setting.reply_draft? then 'draft'
               else 'auto'
               end
        charge = mode != 'test'
        if mode == 'test' && !take_counter("wa_ai:test:#{shop.id}:#{now.to_date}", TEST_DAILY_CAP)
          return fallback(message, conversation_created)
        end
        return fallback(message, conversation_created) if charge && !Wallet.reserve!(shop)

        started = monotonic
        result = Agent.call(conversation: conversation, setting: setting, dry_run: mode == 'draft',
                            allow_actions: mode != 'draft', note: note)
        outcome, reply_message = deliver(result, conversation, setting, mode)
        credits = charge && (reply_message || outcome == 'drafted') ? 1 : 0
        Wallet.refund!(shop) if charge && credits.zero?
        fallback(message, conversation_created) if outcome == 'failed'

        record_run(shop, conversation, result, mode: mode, outcome: outcome, credits: credits, started: started,
                                               trigger_message_id: message.id, reply_message_id: reply_message&.id)
      rescue StandardError => e
        Wallet.refund!(shop) if charge && shop && credits.nil?
        Rails.logger.error("[Whatsapp::Ai::Responder] message=#{message_id} #{e.class}: #{e.message}")
        nil
      end

      def suggest(conversation)
        raise NotConfigured, 'The AI agent is not configured yet.' unless Config.enabled?

        reserved = false
        credits = nil
        shop = conversation.shop
        setting = WhatsappAiSetting.for(shop)
        raise NoCredits, 'You are out of AI credits.' unless Wallet.reserve!(shop)

        reserved = true
        started = monotonic
        result = Agent.call(conversation: conversation, setting: setting, dry_run: true, allow_actions: false)
        text = if result.reply? then result.text
               elsif result.handoff? then result.text.presence || setting.handoff_message
               end
        text = nil if result.skipped?
        credits = text.present? ? 1 : 0
        Wallet.refund!(shop) if credits.zero?
        record_run(shop, conversation, result, mode: 'suggest', outcome: text.present? ? 'drafted' : 'failed',
                                               credits: credits, started: started, reply_text: text)
        { 'text' => text.to_s, 'handoff' => result.handoff?, 'reason' => result.reason, 'note' => result.note,
          'intent' => result.intent, 'actions' => result.actions, 'error' => result.failed? ? result.error : nil }
      rescue Error
        raise
      rescue StandardError => e
        Wallet.refund!(shop) if reserved && credits.nil?
        raise Error, e.message
      end

      def playground(shop, messages:, phone: nil, setting: nil)
        raise NotConfigured, 'The AI agent is not configured yet.' unless Config.enabled?
        unless take_counter("wa_ai:playground:#{shop.id}:#{Date.current}", PLAYGROUND_DAILY_CAP)
          raise RateLimited, "You can run #{PLAYGROUND_DAILY_CAP} test chats a day. Try again tomorrow."
        end

        setting ||= WhatsappAiSetting.for(shop)
        conversation = playground_conversation(shop, phone)
        history = Array(messages).last(ContextBuilder::HISTORY_LIMIT).filter_map do |m|
          m = m.to_h.stringify_keys
          text = m['text'].to_s.strip.first(1000)
          next if text.blank?

          { 'role' => m['role'].to_s == 'customer' ? 'customer' : 'store', 'source' => 'ai', 'text' => text }
        end
        started = monotonic
        result = Agent.call(conversation: conversation, setting: setting, history: history, dry_run: true)
        text = result.reply? ? result.text : (result.handoff? ? (result.text.presence || setting.handoff_message) : nil)
        record_run(shop, conversation.persisted? ? conversation : nil, result,
                   mode: 'playground', outcome: outcome_for(result), credits: 0, started: started, reply_text: text)
        {
          'reply' => text.to_s,
          'kind' => result.kind.to_s,
          'intent' => result.intent,
          'handoff_reason' => result.reason,
          'note' => result.note,
          'actions' => result.actions,
          'error' => result.failed? ? result.error : nil,
          'customer' => { 'matched' => conversation.persisted? || orders_found?(shop, conversation) }
        }
      end

      def outcome_for(result)
        return 'skipped' if result.skipped?
        return 'failed' if result.failed?

        result.handoff? ? 'handoff' : 'replied'
      end

      def deliver(result, conversation, setting, mode)
        return ['skipped', nil] if result.skipped?
        return ['failed', nil] if result.failed?

        if result.reply?
          if mode == 'draft'
            WhatsappConversation.where(id: conversation.id)
                                .update_all(ai_draft: result.text, ai_draft_at: Time.current, updated_at: Time.current)
            return ['drafted', nil]
          end
          message = send_text(conversation, result.text)
          mark_handled!(conversation) if message
          return [message ? 'replied' : 'failed', message]
        end

        message = mode == 'draft' ? nil : send_text(conversation, result.text.presence || setting.handoff_message)
        handoff!(conversation, result)
        ['handoff', message]
      end

      def send_text(conversation, text)
        Whatsapp::Inbox::FreeformSender.call(conversation: conversation, agent: nil, source: 'ai', text: text)
      rescue Whatsapp::Inbox::FreeformSender::Error => e
        Rails.logger.warn("[Whatsapp::Ai::Responder] send failed conv=#{conversation.id}: #{e.class}: #{e.message}")
        nil
      end

      def mark_handled!(conversation)
        Whatsapp::Inbox::ConversationState.set_status!(conversation.reload, 'pending', by: 'ai')
        WhatsappConversation.where(id: conversation.id).update_all(unread_count: 0, updated_at: Time.current)
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Ai::Responder] status update failed conv=#{conversation.id}: #{e.class}: #{e.message}")
      end

      def handoff!(conversation, result)
        now = Time.current
        note = ["AI handoff (#{result.reason.to_s.tr('_', ' ')}): #{result.note}".strip, conversation.reload.note.presence]
               .compact.join("\n").first(2000)
        WhatsappConversation.where(id: conversation.id)
                            .update_all(ai_handoff_at: now, ai_paused_until: now + HANDOFF_PAUSE, note: note, updated_at: now)
        Whatsapp::Inbox::ConversationState.set_status!(conversation.reload, 'open', by: 'ai')
        key = HANDOFF_LABELS[result.reason.to_s]
        return unless key

        WhatsappInboxLabel.ensure_defaults!(conversation.shop)
        ids = WhatsappInboxLabel.where(shop_id: conversation.shop_id, system_key: key).pluck(:id)
        WhatsappConversationLabel.add!(conversation, ids, source: 'auto')
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Ai::Responder] handoff bookkeeping failed conv=#{conversation.id}: #{e.class}: #{e.message}")
      end

      LimitResult = Struct.new(:reason, :note, keyword_init: true)

      # Free hand-over (no model call, no credit) once a customer hits the store's daily AI reply limit.
      def limit_handoff!(conversation, setting, message, now)
        return nil if conversation.ai_handoff_at.present? && conversation.ai_paused_until.present? &&
                      conversation.ai_paused_until > now
        return nil unless claim!(conversation, message)

        reply = setting.reply_draft? ? nil : send_text(conversation, setting.handoff_message)
        handoff!(conversation, LimitResult.new(
          reason: 'daily_limit',
          note: "Customer reached the daily AI reply limit (#{setting.daily_reply_limit}). Please take over."
        ))
        WhatsappConversation.where(id: conversation.id).update_all(ai_paused_until: now + 24.hours)
        WhatsappAiRun.create(
          shop_id: conversation.shop_id, whatsapp_conversation_id: conversation.id, trigger_message_id: message.id,
          reply_message_id: reply&.id, mode: setting.agent_test? ? 'test' : 'auto', outcome: 'handoff',
          handoff_reason: 'daily_limit', reply_text: reply&.body, actions: [], credits_charged: 0, model: nil
        )
        reply
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Ai::Responder] limit handoff failed conv=#{conversation.id}: #{e.class}: #{e.message}")
        nil
      end

      def pause!(conversation)
        WhatsappConversation.where(id: conversation.id)
                            .update_all(ai_paused_until: Time.current + HANDOFF_PAUSE, updated_at: Time.current)
      end

      def resume!(conversation)
        quiet_before = Time.current - AGENT_QUIET - 1.second
        WhatsappConversation.where(id: conversation.id)
                            .update_all(ai_paused_until: nil, ai_handoff_at: nil, updated_at: Time.current)
        WhatsappConversation.where(id: conversation.id).where('last_agent_reply_at > ?', quiet_before)
                            .update_all(last_agent_reply_at: quiet_before)
      end

      def fallback(message, conversation_created)
        Whatsapp::Inbox::AutoReplyEngine.call(message, conversation_created: conversation_created)
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Ai::Responder] fallback failed message=#{message.id}: #{e.class}: #{e.message}")
        nil
      end

      def message_eligible?(message, now, max_age: MAX_MESSAGE_AGE)
        return false unless message&.inbound?
        return false if SKIP_KINDS.include?(message.kind.to_s)
        return false if message.occurred_at.nil? || message.occurred_at < now - max_age
        return false if Whatsapp::Inbox::AutoReplyEngine.reserved_payload?(message)

        text = message.body.to_s.strip.downcase
        !(OPT_OUT_KEYWORDS.include?(text) || text.start_with?('stop'))
      end

      def paused?(conversation, now)
        conversation.ai_paused_until.present? && conversation.ai_paused_until > now
      end

      def agent_replied_recently?(conversation, now)
        conversation.last_agent_reply_at.present? && conversation.last_agent_reply_at > now - AGENT_QUIET
      end

      def newer_inbound?(conversation, message)
        WhatsappConversationMessage.where(whatsapp_conversation_id: conversation.id, direction: :inbound)
                                   .where('id > ?', message.id)
                                   .where.not(kind: SKIP_KINDS)
                                   .exists?
      end

      def daily_cap_reached?(conversation, now, limit = CONVERSATION_DAILY_CAP)
        return false if limit.to_i <= 0

        WhatsappAiRun.where(whatsapp_conversation_id: conversation.id, mode: %w[auto draft test],
                            outcome: %w[replied drafted handoff])
                     .where('created_at > ?', now - 24.hours)
                     .count >= limit.to_i
      end

      def claim!(conversation, message)
        WhatsappConversation.where(id: conversation.id)
                            .where('ai_last_message_id IS NULL OR ai_last_message_id < ?', message.id)
                            .update_all(ai_last_message_id: message.id) == 1
      end

      def take_counter(key, limit)
        count = Rails.cache.increment(key, 1, expires_in: 1.day)
        if count.nil?
          Rails.cache.write(key, 1, expires_in: 1.day)
          count = 1
        end
        count <= limit
      rescue StandardError
        true
      end

      def playground_conversation(shop, phone)
        digits = phone.to_s.gsub(/\D/, '')
        account = shop.whatsapp_accounts.where(custom_branded_client_id: nil).find_by(is_default: true) ||
                  shop.whatsapp_accounts.where(custom_branded_client_id: nil).order(:id).first
        if digits.length >= 8
          existing = WhatsappConversation.where(shop_id: shop.id, phone_last10: digits.last(10))
                                         .order(last_message_at: :desc).first
          return existing if existing
        end
        WhatsappConversation.new(
          shop: shop, whatsapp_account: account, customer_wa_id: digits.presence || '0000000000',
          phone_last10: digits.last(10).presence || '0000000000', status: :open, last_inbound_at: Time.current,
          last_message_at: Time.current, status_changed_at: Time.current
        )
      end

      def orders_found?(shop, conversation)
        Whatsapp::Inbox::OrderLookup.scope(shop, conversation.phone_last10).exists?
      end

      def record_run(shop, conversation, result, mode:, outcome:, credits:, started:, trigger_message_id: nil,
                     reply_message_id: nil, reply_text: nil)
        usage = result.usage || {}
        WhatsappAiRun.create!(
          shop_id: shop.id,
          whatsapp_conversation_id: conversation&.id,
          trigger_message_id: trigger_message_id,
          reply_message_id: reply_message_id,
          mode: mode,
          outcome: outcome,
          intent: result.intent,
          reply_text: reply_text || result.text,
          handoff_reason: result.handoff? ? result.reason : nil,
          actions: result.actions || [],
          credits_charged: credits,
          input_tokens: usage[:input].to_i,
          cached_tokens: usage[:cached].to_i,
          output_tokens: usage[:output].to_i,
          cost_usd: Config.cost_usd(input_tokens: usage[:input], cached_tokens: usage[:cached], output_tokens: usage[:output]),
          model: result.model,
          latency_ms: ((monotonic - started) * 1000).round,
          error: result.error
        )
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Ai::Responder] run log failed shop=#{shop.id}: #{e.class}: #{e.message}")
        nil
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
