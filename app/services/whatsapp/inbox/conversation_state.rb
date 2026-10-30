# frozen_string_literal: true

module Whatsapp
  module Inbox
    module ConversationState
      STATUSES = %w[open pending resolved].freeze

      module_function

      def on_inbound!(conversation, at:)
        WhatsappConversation.transaction do
          conversation.lock!
          attrs = {}
          unless conversation.open?
            attrs[:status] = 'open'
            attrs[:status_changed_at] = [at, conversation.status_changed_at].compact.max
            attrs[:unanswered_alert_sent_at] = nil
          end
          if needs_new_episode?(conversation)
            attrs[:current_episode_id] = open_episode!(conversation, at).id
          end
          conversation.update!(attrs) if attrs.any?
        end
        conversation
      end

      def on_agent_reply!(conversation, agent:, at:, resolve: false)
        WhatsappConversation.transaction do
          conversation.lock!
          episode = conversation.current_episode
          if episode && !episode.resolved? && episode.first_response_at.nil?
            episode.update!(first_response_at: at, first_response_agent_id: agent&.id)
          end

          attrs = { last_agent_reply_at: [at, conversation.last_agent_reply_at].compact.max, ai_draft: nil, ai_draft_at: nil }
          target = resolve ? 'resolved' : 'pending'
          if conversation.status != target
            attrs[:status] = target
            attrs[:status_changed_at] = Time.current
          end
          if resolve
            close_episode!(episode, 'agent')
            attrs.merge!(ai_paused_until: nil, ai_handoff_at: nil, ai_draft: nil)
          end
          conversation.update!(attrs)
        end
        conversation
      end

      def set_status!(conversation, status, agent: nil, by: 'agent')
        status = status.to_s
        raise ArgumentError, "unknown status #{status.inspect}" unless STATUSES.include?(status)

        WhatsappConversation.transaction do
          conversation.lock!
          next if conversation.status == status

          now = Time.current
          attrs = { status: status, status_changed_at: now }
          if status == 'resolved'
            close_episode!(conversation.current_episode, by)
            attrs.merge!(ai_paused_until: nil, ai_handoff_at: nil, ai_draft: nil)
          elsif needs_new_episode?(conversation)
            attrs[:current_episode_id] = open_episode!(conversation, now).id
          end
          attrs[:unanswered_alert_sent_at] = nil if status == 'open'
          conversation.update!(attrs)
        end
        conversation
      end

      def resolve!(conversation, by: 'auto')
        set_status!(conversation, 'resolved', by: by)
      end

      def needs_new_episode?(conversation)
        episode = conversation.current_episode
        episode.nil? || episode.resolved?
      end

      def open_episode!(conversation, at)
        WhatsappConversationEpisode.create!(
          whatsapp_conversation_id: conversation.id,
          shop_id: conversation.shop_id,
          opened_at: at
        )
      end

      def close_episode!(episode, by)
        return if episode.nil? || episode.resolved?

        episode.update!(resolved_at: Time.current, resolved_by: by.to_s)
      end
    end
  end
end
