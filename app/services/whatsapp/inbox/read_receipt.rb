# frozen_string_literal: true

module Whatsapp
  module Inbox
    # Marking the latest inbound message read also marks every earlier one read
    # (Meta contract), so only the newest id is sent.
    class ReadReceipt < ApplicationService
      REQUEST_TIMEOUT = 10
      MAX_AGE = 29.days

      def initialize(conversation)
        @conversation = conversation
      end

      def call
        return false unless eligible?

        account = conversation.whatsapp_account
        return false unless account&.ready_to_send?

        meta_id = conversation.last_inbound_meta_message_id
        Meta::GraphClient.new(token: account.system_user_token, timeout: REQUEST_TIMEOUT).post(
          "#{account.phone_number_id}/messages",
          body: { messaging_product: 'whatsapp', status: 'read', message_id: meta_id }
        )
        WhatsappConversation.where(id: conversation.id).update_all(read_receipt_meta_message_id: meta_id)
        true
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Inbox::ReadReceipt] conversation=#{conversation&.id} #{e.class}: #{e.message}")
        false
      end

      private

      attr_reader :conversation

      def eligible?
        return false if conversation.nil? || conversation.last_inbound_meta_message_id.blank?
        return false if conversation.last_inbound_meta_message_id == conversation.read_receipt_meta_message_id
        return false if conversation.last_inbound_at.nil? || conversation.last_inbound_at < MAX_AGE.ago

        WhatsappInboxSetting.for(conversation.shop).read_receipts
      end
    end
  end
end
