# frozen_string_literal: true

module Api
  module Whatsapp
    module Ai
      class RunsController < BaseController
        LIMIT = 50

        def index
          scope = WhatsappAiRun.where(shop_id: @shop.id).where.not(mode: 'playground')
          runs = scope.order(created_at: :desc).limit(LIMIT).to_a
          conversations = WhatsappConversation.where(shop_id: @shop.id, id: runs.map(&:whatsapp_conversation_id).compact.uniq)
                                              .index_by(&:id)
          render json: {
            runs: runs.map { |r| r.as_api_json(conversations[r.whatsapp_conversation_id]) },
            stats: stats(scope.where('created_at > ?', 7.days.ago))
          }
        end

        private

        def stats(scope)
          rows = scope.pluck(:outcome, :actions, :credits_charged)
          actions = rows.flat_map { |r| Array(r[1]) }.select { |a| a.is_a?(Hash) && a['ok'] && !a['dry_run'] }
          {
            'replies' => rows.count { |r| r[0] == 'replied' },
            'handoffs' => rows.count { |r| r[0] == 'handoff' },
            'drafts' => rows.count { |r| r[0] == 'drafted' },
            'cod_confirmed' => actions.count { |a| a['type'] == 'confirm_cod_order' },
            'payment_links' => actions.count { |a| a['type'] == 'send_payment_link' },
            'discounts' => actions.count { |a| a['type'] == 'get_discount_code' && !a['reused'] },
            'orders_placed' => actions.count { |a| a['type'] == 'place_cod_order' },
            'credits' => rows.sum { |r| r[2].to_i }
          }
        end
      end
    end
  end
end
