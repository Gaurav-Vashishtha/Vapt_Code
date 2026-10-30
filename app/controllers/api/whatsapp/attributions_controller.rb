module Api
  module Whatsapp
    class AttributionsController < AuthenticatedController
      MAX_IDS = 200
      DEFAULT_DAYS = 30
      MAX_DAYS = 365

      def campaigns
        ids = Array(params[:ids]).flat_map { |v| v.to_s.split(',') }.first(MAX_IDS)
        render json: { campaigns: ::Whatsapp::AttributionReport.campaign_totals(@shop, ids) }
      end

      def campaign
        campaign = WhatsappCampaign.find_by(id: params[:id], shop_id: @shop.id)
        return render(json: { error: 'Campaign not found' }, status: :not_found) unless campaign

        render json: ::Whatsapp::AttributionReport.campaign_detail(@shop, campaign)
      end

      def notifications
        days = params[:days].to_i
        days = DEFAULT_DAYS unless days.positive?
        render json: ::Whatsapp::AttributionReport.notification_totals(@shop, [days, MAX_DAYS].min)
      end

      def engagement
        days = params[:days].to_i
        days = DEFAULT_DAYS unless days.positive?
        render json: ::Whatsapp::EngagementReport.call(@shop, [days, MAX_DAYS].min)
      end
    end
  end
end
