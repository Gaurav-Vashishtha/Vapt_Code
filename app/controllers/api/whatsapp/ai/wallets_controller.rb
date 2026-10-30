# frozen_string_literal: true

module Api
  module Whatsapp
    module Ai
      class WalletsController < BaseController
        def show
          if WhatsappAiCreditTransaction.pending.where(shop_id: @shop.id).exists?
            ::Whatsapp::Ai::Recharge.reconcile_pending!(@shop)
            @wallet = nil
          end
          render json: payload
        end

        def update
          attrs = params.to_unsafe_h
          wallet.auto_recharge = ActiveModel::Type::Boolean.new.cast(attrs['auto_recharge']) == true if attrs.key?('auto_recharge')
          wallet.auto_recharge_pack = attrs['auto_recharge_pack'].presence if attrs.key?('auto_recharge_pack')
          wallet.auto_recharge_pack ||= WhatsappAiWallet::PACKS.keys.first if wallet.auto_recharge
          if wallet.auto_recharge && @shop.charge_id.blank?
            return render_error('no_plan', 'Auto-recharge needs an active COD King plan. Buy a pack instead.')
          end

          wallet.auto_recharge_failed_at = nil
          wallet.auto_recharge_error = nil
          return render_error('invalid', wallet.errors.full_messages.first) unless wallet.save

          ::Whatsapp::Ai::Wallet.maybe_auto_recharge(@shop)
          render json: payload
        end

        private

        def payload
          {
            wallet: wallet.as_api_json,
            auto_recharge_available: @shop.charge_id.present?,
            transactions: WhatsappAiCreditTransaction.where(shop_id: @shop.id)
                                                     .where.not(status: 'pending')
                                                     .order(created_at: :desc).limit(25)
                                                     .map(&:as_api_json),
            usage: usage_json
          }
        end

        def usage_json
          scope = WhatsappAiRun.where(shop_id: @shop.id).where('created_at > ?', 30.days.ago)
          { 'credits_30d' => scope.sum(:credits_charged).to_i }
        end
      end
    end
  end
end
