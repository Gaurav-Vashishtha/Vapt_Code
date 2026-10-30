# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class SavedRepliesController < BaseController
        before_action :load_saved_reply, only: %i[update destroy used]

        def index
          replies = WhatsappSavedReply.where(shop_id: @shop.id).ordered
          render json: { saved_replies: replies.map(&:as_inbox_json) }
        end

        def create
          reply = WhatsappSavedReply.new(saved_reply_params.merge(shop_id: @shop.id))
          save_and_render(reply, :created)
        end

        def update
          @saved_reply.assign_attributes(saved_reply_params)
          save_and_render(@saved_reply, :ok)
        end

        def destroy
          @saved_reply.destroy!
          render json: { ok: true }
        end

        def used
          render json: { saved_reply: @saved_reply.record_use!.as_inbox_json }
        end

        private

        def load_saved_reply
          @saved_reply = WhatsappSavedReply.where(shop_id: @shop.id).find_by(id: params[:id])
          render_error('not_found', 'Saved reply not found', :not_found) unless @saved_reply
        end

        def saved_reply_params
          params.slice(:title, :shortcut, :body).permit(:title, :shortcut, :body).to_h
        end

        def save_and_render(reply, status)
          if reply.save
            render json: { saved_reply: reply.as_inbox_json }, status: status
          else
            render_error('invalid', reply.errors.full_messages.first)
          end
        rescue ActiveRecord::RecordNotUnique
          render_error('invalid', 'Shortcut is already used by another saved reply')
        end
      end
    end
  end
end
