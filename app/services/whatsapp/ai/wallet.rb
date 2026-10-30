# frozen_string_literal: true

module Whatsapp
  module Ai
    module Wallet
      module_function

      def balance(shop)
        WhatsappAiWallet.for(shop).balance
      end

      def reserve!(shop, credits = 1)
        wallet = WhatsappAiWallet.for(shop)
        taken = WhatsappAiWallet.where(id: wallet.id)
                                .where('balance >= ?', credits)
                                .update_all(['balance = balance - ?, lifetime_used = lifetime_used + ?, updated_at = ?',
                                             credits, credits, Time.current]) == 1
        maybe_auto_recharge(shop) if taken
        taken
      end

      def refund!(shop, credits = 1)
        WhatsappAiWallet.where(shop_id: shop.id)
                        .update_all(['balance = balance + ?, lifetime_used = GREATEST(lifetime_used - ?, 0), updated_at = ?',
                                     credits, credits, Time.current])
      end

      def grant_free!(shop)
        wallet = WhatsappAiWallet.for(shop)
        granted = WhatsappAiWallet.where(id: wallet.id, free_granted_at: nil)
                                  .update_all(free_granted_at: Time.current, updated_at: Time.current) == 1
        return false unless granted

        credit!(shop, WhatsappAiWallet::FREE_CREDITS, kind: 'grant', note: 'Free credits to get started')
        true
      end

      def credit!(shop, credits, kind:, transaction: nil, **attrs)
        wallet = WhatsappAiWallet.for(shop)
        WhatsappAiWallet.transaction do
          wallet.lock!
          wallet.balance += credits
          wallet.lifetime_purchased += credits if credits.positive? && kind != 'refund'
          wallet.auto_recharge_failed_at = nil if kind == 'auto_recharge'
          wallet.auto_recharge_error = nil if kind == 'auto_recharge'
          wallet.save!
          row = transaction || WhatsappAiCreditTransaction.new(shop_id: shop.id)
          row.assign_attributes(attrs.merge(kind: kind, credits: credits, status: 'completed', balance_after: wallet.balance))
          row.save!
          row
        end
      end

      def maybe_auto_recharge(shop)
        wallet = WhatsappAiWallet.find_by(shop_id: shop.id)
        return unless wallet&.auto_recharge && wallet.auto_recharge_pack.present? && wallet.low?
        return if wallet.auto_recharge_failed_at.present? && wallet.auto_recharge_failed_at > 1.day.ago

        AutoRechargeJob.perform_async(shop.id)
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Ai::Wallet] auto-recharge enqueue failed shop=#{shop.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
