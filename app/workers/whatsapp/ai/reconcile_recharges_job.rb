# frozen_string_literal: true

module Whatsapp
  module Ai
    class ReconcileRechargesJob < ApplicationJob
      sidekiq_options queue: 'default', retry: false

      def perform
        shop_ids = WhatsappAiCreditTransaction.pending.where(kind: 'purchase')
                                              .where('created_at < ?', 10.minutes.ago)
                                              .distinct.pluck(:shop_id)
        Shop.where(id: shop_ids).find_each { |shop| Recharge.reconcile_pending!(shop) }
      end
    end
  end
end
