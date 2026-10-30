# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class ConversationsController < BaseController
        NOTE_MAX = 5000

        before_action :load_conversation, except: %i[index]

        def index
          result = ::Whatsapp::Inbox::ConversationQuery.call(shop: @shop, agent: current_agent, params: params)
          render json: {
            conversations: ::Whatsapp::Inbox::ConversationSerializer.list(result[:conversations], shop: @shop, current_agent: current_agent),
            next_cursor: result[:next_cursor],
            counts: result[:counts]
          }
        end

        def show
          render json: { conversation: conversation_detail(@conversation) }
        end

        def update
          status = params.key?(:status) ? params[:status].to_s : nil
          if status && !::Whatsapp::Inbox::ConversationQuery::STATUSES.include?(status)
            return render_error('invalid', 'Unknown status')
          end

          attrs = {}
          if params.key?(:assignee_id)
            assignee = resolve_assignee(params[:assignee_id])
            return render_error('invalid', 'Unknown agent') if assignee == :unknown

            attrs[:assignee_agent_id] = assignee&.id
          end
          if params.key?(:note)
            note = params[:note].to_s
            return render_error('invalid', "Note is limited to #{NOTE_MAX} characters") if note.length > NOTE_MAX

            attrs[:note] = note.presence
          end

          WhatsappConversation.transaction do
            @conversation.update!(attrs) if attrs.any?
            if status && status != @conversation.status
              ::Whatsapp::Inbox::ConversationState.set_status!(@conversation, status, agent: current_agent, by: 'agent')
            end
          end
          render json: { conversation: conversation_detail(@conversation.reload) }
        end

        def read
          WhatsappConversation.where(id: @conversation.id, shop_id: @shop.id)
                              .update_all(unread_count: 0, updated_at: Time.current)
          if @conversation.last_inbound_meta_message_id.present? &&
             @conversation.last_inbound_meta_message_id != @conversation.read_receipt_meta_message_id
            ::Whatsapp::Inbox::MarkReadJob.perform_async(@conversation.id)
          end
          render json: { ok: true }
        end

        def unread
          WhatsappConversation.where(id: @conversation.id, shop_id: @shop.id)
                              .update_all(['unread_count = GREATEST(unread_count, 1), updated_at = ?', Time.current])
          render json: { ok: true }
        end

        def block
          phone = @conversation.customer_wa_id.to_s.gsub(/\D/, '')
          return render_error('invalid', 'This customer has no phone number') if phone.blank?

          WhatsappOptOut.record!(shop_id: @shop.id, phone_normalized: phone, reason: 'inbox_block', source: 'inbox')
          render json: { opted_out: opted_out? }
        end

        def unblock
          WhatsappOptOut.where(shop_id: @shop.id, phone_normalized: phone_keys).delete_all
          render json: { opted_out: opted_out? }
        end

        private

        def resolve_assignee(raw)
          return nil if raw.blank?
          return :unknown unless raw.to_s.match?(/\A\d+\z/)

          WhatsappInboxAgent.find_by(shop_id: @shop.id, id: raw.to_i) || :unknown
        end

        def phone_keys
          ::Whatsapp::Inbox::ConversationSerializer.phone_keys(@conversation)
        end

        def opted_out?
          WhatsappOptOut.where(shop_id: @shop.id, phone_normalized: phone_keys).exists?
        end
      end
    end
  end
end
