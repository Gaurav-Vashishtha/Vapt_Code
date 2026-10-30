# frozen_string_literal: true

module Whatsapp
  module Inbox
    class Report
      PERIOD = 7.days
      MAX_AGENTS = 20

      def self.call(shop)
        new(shop).call
      end

      def initialize(shop)
        @shop = shop
        @since = PERIOD.ago
      end

      def call
        {
          'first_response_median_seconds' => first_response_median,
          'open' => WhatsappConversation.where(shop_id: @shop.id, status: :open).count,
          'resolved_this_week' => resolved_count,
          'replies_by_agent' => replies_by_agent
        }
      end

      private

      def first_response_median
        value = WhatsappConversationEpisode
                .where(shop_id: @shop.id)
                .where('whatsapp_conversation_episodes.opened_at >= ?', @since)
                .where.not(first_response_at: nil)
                .pick(Arel.sql('percentile_cont(0.5) WITHIN GROUP (ORDER BY GREATEST(EXTRACT(EPOCH FROM ' \
                               '(whatsapp_conversation_episodes.first_response_at - whatsapp_conversation_episodes.opened_at)), 0))'))
        value&.to_f&.round
      end

      def resolved_count
        WhatsappConversationEpisode
          .where(shop_id: @shop.id)
          .where('whatsapp_conversation_episodes.resolved_at >= ?', @since)
          .count
      end

      def replies_by_agent
        failed = WhatsappConversationMessage.statuses.fetch('failed')
        counts = WhatsappConversationMessage
                 .where(shop_id: @shop.id, source: 'agent')
                 .where.not(agent_id: nil)
                 .where('whatsapp_conversation_messages.created_at >= ?', @since)
                 .where('whatsapp_conversation_messages.status IS NULL OR whatsapp_conversation_messages.status <> ?', failed)
                 .group(:agent_id)
                 .count
        return [] if counts.empty?

        agents = WhatsappInboxAgent.where(shop_id: @shop.id, id: counts.keys).index_by(&:id)
        counts.sort_by { |id, n| [-n, id] }.first(MAX_AGENTS).filter_map do |id, n|
          agent = agents[id]
          next unless agent

          { 'agent_id' => id, 'name' => ConversationSerializer.agent_name(agent), 'replies' => n }
        end
      end
    end
  end
end
