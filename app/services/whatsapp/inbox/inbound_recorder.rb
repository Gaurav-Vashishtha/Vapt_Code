# frozen_string_literal: true

module Whatsapp
  module Inbox
    class InboundRecorder < ApplicationService
      NO_ATTENTION_KINDS = %w[reaction system].freeze

      def self.disabled?
        ENV['WHATSAPP_INBOX_DISABLED'].present?
      end

      def initialize(inbound, profile_name: nil, backfill: false)
        @inbound = inbound
        @profile_name = profile_name.to_s.strip.presence
        @backfill = backfill
      end

      def call
        return nil if self.class.disabled? || inbound.nil? || inbound.shop_id.nil?

        account = inbound.whatsapp_account
        return nil if account.nil? || account.shop_id != inbound.shop_id

        existing = WhatsappConversationMessage.find_by(whatsapp_inbound_message_id: inbound.id)
        return existing if existing

        wa_id = inbound.from_phone.to_s.gsub(/\D/, '')
        return nil if wa_id.length < 7

        parsed = InboundParser.parse(inbound.meta_payload)
        attention = !NO_ATTENTION_KINDS.include?(parsed[:kind])
        at = inbound.received_at || Time.current

        conversation, created = find_or_create_conversation(account, wa_id, at, parsed, attention)
        return nil if conversation.nil?

        message = record(conversation, parsed, at, attention)
        enqueue_followups(message, conversation, created) unless backfill
        message
      rescue ActiveRecord::RecordNotUnique
        WhatsappConversationMessage.find_by(whatsapp_inbound_message_id: inbound.id)
      end

      private

      attr_reader :inbound, :profile_name, :backfill

      def record(conversation, parsed, at, attention)
        media = parsed[:media]
        WhatsappConversation.transaction do
          conversation.lock!
          message = WhatsappConversationMessage.create!(
            whatsapp_conversation_id: conversation.id,
            shop_id: conversation.shop_id,
            direction: :inbound,
            source: 'customer',
            kind: parsed[:kind],
            body: parsed[:body],
            content: parsed[:content] || {},
            meta_message_id: inbound.meta_message_id,
            reply_to_meta_message_id: parsed[:reply_to_meta_message_id],
            whatsapp_inbound_message_id: inbound.id,
            whatsapp_message_log_id: nil,
            media_id: media && media[:id],
            media_mime_type: media && media[:mime_type],
            media_file_name: media && media[:file_name],
            media_sha256: media && media[:sha256],
            media_state: media ? :pending : :none,
            occurred_at: at
          )

          attrs = {}
          attrs[:customer_name] = profile_name if profile_name && profile_name != conversation.customer_name
          if parsed[:counts_for_window] && at >= conversation.last_inbound_at
            attrs[:last_inbound_at] = at
            attrs[:last_inbound_meta_message_id] = inbound.meta_message_id
          end
          attrs[:unread_count] = conversation.unread_count + 1 if attention && !backfill
          if at >= conversation.last_message_at
            attrs[:last_message_at] = at
            attrs[:last_message_direction] = 'inbound'
            attrs[:last_message_preview] = preview(parsed)
          end
          conversation.update!(attrs) if attrs.any?
          ConversationState.on_inbound!(conversation, at: at) if attention && !backfill
          message
        end
      end

      def preview(parsed)
        WhatsappConversationMessage.preview_for(
          kind: parsed[:kind], body: parsed[:body], content: parsed[:content],
          file_name: parsed[:media] && parsed[:media][:file_name]
        ).truncate(200)
      end

      # A reaction or system notice alone never starts a ticket. An unsupported
      # message does, but Meta has not confirmed the window for it, so the
      # window starts closed until the customer sends something we can read.
      def find_or_create_conversation(account, wa_id, at, parsed, attention)
        conversation = WhatsappConversation.find_by(whatsapp_account_id: account.id, customer_wa_id: wa_id)
        return [conversation, false] if conversation

        orphan = WhatsappConversation.where(shop_id: inbound.shop_id, whatsapp_account_id: nil, customer_wa_id: wa_id)
                                     .order(last_inbound_at: :desc).first
        if orphan
          orphan.update!(whatsapp_account_id: account.id)
          return [orphan, false]
        end
        return [nil, false] unless attention

        conversation = WhatsappConversation.create!(
          shop_id: inbound.shop_id,
          whatsapp_account_id: account.id,
          customer_wa_id: wa_id,
          phone_last10: WhatsappConversation.phone_last10(wa_id),
          customer_name: profile_name,
          status: :open,
          status_changed_at: at,
          last_inbound_at: at,
          last_message_at: at,
          window_closed_hint_at: parsed[:counts_for_window] ? nil : at
        )
        [conversation, true]
      rescue ActiveRecord::RecordNotUnique
        [WhatsappConversation.find_by(whatsapp_account_id: account.id, customer_wa_id: wa_id), false]
      end

      def enqueue_followups(message, conversation, created)
        ProcessInboundJob.perform_async(message.id, created)
        BackfillThreadJob.perform_async(conversation.id) if created
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::InboundRecorder] enqueue failed message=#{message.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
