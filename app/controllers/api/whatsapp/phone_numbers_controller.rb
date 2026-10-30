module Api
  module Whatsapp
    class PhoneNumbersController < AuthenticatedController
      before_action :load_account

      def status
        result = Meta::PhoneNumberService.call(account: @account, operation: :status)
        render json: { account: serialize_account, meta: result }
      rescue Meta::PhoneNumberService::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def register
        Meta::PhoneNumberService.call(account: @account, operation: :register, pin: params[:pin])
        render json: { account: serialize_account }
      rescue Meta::PhoneNumberService::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def request_code
        Meta::PhoneNumberService.call(
          account: @account,
          operation: :request_code,
          code_method: params.fetch(:code_method, 'SMS'),
          language: params.fetch(:language, 'en')
        )
        render json: { ok: true }
      rescue Meta::PhoneNumberService::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def verify_code
        Meta::PhoneNumberService.call(account: @account, operation: :verify_code, code: params[:code])
        render json: { account: serialize_account }
      rescue Meta::PhoneNumberService::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      # Target a specific number when account_id is supplied (multi-number),
      # else the shop default.
      def load_account
        @account = if params[:account_id].present?
                     @shop.whatsapp_accounts.find_by(id: params[:account_id])
                   else
                     @shop.default_whatsapp_account
                   end
        render(json: { error: 'no WhatsApp account connected' }, status: :not_found) unless @account
      end

      def serialize_account
        {
          status: @account.status,
          display_phone_number: @account.display_phone_number,
          verified_name: @account.verified_name,
          quality_rating: @account.quality_rating,
          last_synced_at: @account.last_synced_at,
          registered_at: @account.registered_at
        }
      end
    end
  end
end
