# frozen_string_literal: true

module Whatsapp
  module Inbox
    class ProcessInboundJob < ApplicationJob
      sidekiq_options queue: 'whatsapp_inbox', retry: false

      def perform(message_id, conversation_created = false)
        message = WhatsappConversationMessage.find_by(id: message_id)
        return unless message

        if message.media_pending? && MediaStore.enabled?
          begin
            DownloadMediaJob.perform_async(message.id)
          rescue StandardError => e
            Rails.logger.error("[Whatsapp::Inbox::ProcessInboundJob] media enqueue failed message=#{message.id}: #{e.class}: #{e.message}")
          end
        end

        Automations.on_inbound(message, conversation_created: conversation_created ? true : false)
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::ProcessInboundJob] message=#{message_id} #{e.class}: #{e.message}")
      end
    end
  end
end
