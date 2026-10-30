# frozen_string_literal: true

module Whatsapp
  module Ai
    class ReplyJob < ApplicationJob
      sidekiq_options queue: 'whatsapp_inbox', retry: false

      DEBOUNCE = 8.seconds

      def perform(message_id, conversation_created = false, takeover = false)
        Responder.on_inbound(message_id, conversation_created: conversation_created ? true : false,
                                         takeover: takeover ? true : false)
      end
    end
  end
end
