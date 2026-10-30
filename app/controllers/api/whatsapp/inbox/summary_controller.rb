# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class SummaryController < BaseController
        POLL_SECONDS = 30

        def show
          enabled = inbox_accounts.exists?
          scope = WhatsappConversation.where(shop_id: @shop.id)
          render json: {
            enabled: enabled,
            unread_conversations: scope.where('whatsapp_conversations.unread_count > 0').count,
            open: scope.where(status: :open).count,
            poll_seconds: POLL_SECONDS
          }
        end
      end
    end
  end
end
