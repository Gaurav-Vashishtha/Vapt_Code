# frozen_string_literal: true

module Api
  module Whatsapp
    module Ai
      class RechargesController < BaseController
        def create
          url = ::Whatsapp::Ai::Recharge.start!(@shop, params[:pack])
          render json: { confirmation_url: url }
        rescue ::Whatsapp::Ai::Recharge::Error => e
          render_error('recharge_failed', "Couldn't start the purchase: #{e.message}")
        end

        def confirm
          row = ::Whatsapp::Ai::Recharge.confirm!(@shop, params[:charge_id])
          return render_error('not_found', 'We could not find this purchase.', :not_found) unless row

          render json: { status: row.status, credits: row.credits, wallet: WhatsappAiWallet.for(@shop).as_api_json }
        end
      end
    end
  end
end
