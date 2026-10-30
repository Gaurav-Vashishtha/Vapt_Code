module Api
  module Whatsapp
    class TestMessagesController < AuthenticatedController
      before_action :load_account

      def create
        result = Meta::TestMessageService.call(
          account: @account,
          to: params[:to],
          template_name: params[:template_name],
          language: params.fetch(:language, 'en_US')
        )
        render json: result, status: :created
      rescue Meta::TestMessageService::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def load_account
        @account = if params[:account_id].present?
                     @shop.whatsapp_accounts.find_by(id: params[:account_id])
                   else
                     @shop.default_whatsapp_account
                   end
        render(json: { error: 'no WhatsApp account connected' }, status: :not_found) unless @account
      end
    end
  end
end
