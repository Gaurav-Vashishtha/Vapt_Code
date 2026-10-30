# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class AgentsController < BaseController
        SEEN_WITHIN = 90.days
        MAX_AGENTS = 200

        def me
          agent = ::Whatsapp::Inbox::AgentProfileFetcher.call(shop: @shop, agent: current_agent, session_token: session_token)
          render json: { agent: serialize(agent), agents: agent_list }
        end

        def index
          render json: { agents: agent_list }
        end

        private

        def agent_list
          scope = WhatsappInboxAgent.where(shop_id: @shop.id)
          scope = if current_agent.id
                    scope.where('whatsapp_inbox_agents.last_seen_at >= ? OR whatsapp_inbox_agents.id = ?', SEEN_WITHIN.ago, current_agent.id)
                  else
                    scope.where('whatsapp_inbox_agents.last_seen_at >= ?', SEEN_WITHIN.ago)
                  end
          scope.order(Arel.sql('whatsapp_inbox_agents.name IS NULL, LOWER(whatsapp_inbox_agents.name), whatsapp_inbox_agents.id'))
               .limit(MAX_AGENTS)
               .map { |a| serialize(a) }
        end

        def serialize(agent)
          ::Whatsapp::Inbox::ConversationSerializer.agent_json(agent, current_agent)
        end
      end
    end
  end
end
