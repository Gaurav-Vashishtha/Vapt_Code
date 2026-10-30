# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class ConversationAiController < BaseController
        before_action :load_conversation

        def suggest
          result = ::Whatsapp::Ai::Responder.suggest(@conversation)
          render json: result
        rescue ::Whatsapp::Ai::Responder::NoCredits => e
          render_error('no_credits', e.message, :payment_required)
        rescue ::Whatsapp::Ai::Responder::Error => e
          render_error('ai_failed', e.message)
        end

        def pause
          ::Whatsapp::Ai::Responder.pause!(@conversation)
          render json: { conversation: conversation_detail(@conversation.reload) }
        end

        def resume
          ::Whatsapp::Ai::Responder.resume!(@conversation)
          render json: { conversation: conversation_detail(@conversation.reload) }
        end

        def dismiss_draft
          WhatsappConversation.where(id: @conversation.id).update_all(ai_draft: nil, ai_draft_at: nil, updated_at: Time.current)
          render json: { conversation: conversation_detail(@conversation.reload) }
        end
      end
    end
  end
end
