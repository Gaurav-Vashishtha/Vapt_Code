# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class ConversationLabelsController < BaseController
        def update
          conversation = load_conversation
          labels = WhatsappConversationLabel.replace!(conversation, Array(params[:label_ids]))
          render json: { labels: labels.map(&:as_inbox_json) }
        end
      end
    end
  end
end
