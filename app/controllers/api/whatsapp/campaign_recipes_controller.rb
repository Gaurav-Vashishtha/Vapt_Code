module Api
  module Whatsapp
    class CampaignRecipesController < AuthenticatedController
      def index
        render json: { recipes: ::Whatsapp::CampaignRecipes.index(@shop, account: find_account) }
      end

      def apply
        result = ::Whatsapp::CampaignRecipes.apply!(@shop, params[:id], account: find_account)
        render json: result, status: :created
      rescue ::Whatsapp::CampaignRecipes::UnknownRecipe
        render json: { error: 'Recipe not found' }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Could not set up the audience for this recipe' }, status: :unprocessable_entity
      end

      private

      def find_account
        return nil if params[:account_id].blank?
        @shop.whatsapp_accounts.find_by(id: params[:account_id])
      end
    end
  end
end
