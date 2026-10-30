# frozen_string_literal: true

module Api
  module Sidekick
    # WhatsApp broadcast campaigns for Sidekick.
    #
    # - index (data extension, read-only): lists campaigns as resource links
    #   whose mimeType `application/campaign` matches the codk-sidekick-campaign
    #   action extension, so Sidekick can offer "edit" on a result.
    # - options / create / update (action extension, admin.app.intent.render):
    #   the intent form loads its choices from `options` and saves a campaign
    #   only when the merchant clicks Save. Campaigns are saved as drafts;
    #   sending still happens from COD King's Campaigns page (launch).
    class WhatsappCampaignsController < BaseController
      EDITABLE = %w[draft scheduled].freeze

      def index
        scope = WhatsappCampaign.where(shop_id: @shop.id).order(updated_at: :desc)
        scope = scope.where(status: params[:status]) if WhatsappCampaign::STATUSES.include?(params[:status].to_s)
        if params[:query].present?
          scope = scope.where('name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip)}%")
        end

        render json: { results: scope.includes(:whatsapp_template).limit(result_limit).map { |c| campaign_link(c) } }
      end

      def options
        templates = @shop.whatsapp_templates.where(status: :approved).order(:name).limit(50)
        render json: {
          audience_sources: WhatsappCampaign::AUDIENCE_SOURCES - %w[csv],
          templates: templates.map { |t| { id: t.id, name: t.name, language: t.language, category: t.category } },
          accounts_connected: @shop.whatsapp_accounts.count,
          timezone: shop_tz.name
        }
      end

      def show
        campaign = find_campaign or return
        render json: { campaign: campaign_json(campaign) }
      end

      def create
        campaign = WhatsappCampaign.new(campaign_attributes.merge(shop_id: @shop.id, status: 'draft'))
        return render(json: { campaign: campaign_json(campaign) }) if campaign.save

        render json: { error: campaign.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      def update
        campaign = find_campaign or return
        unless EDITABLE.include?(campaign.status)
          return render json: { error: "A #{campaign.status} campaign can't be edited here." }, status: :unprocessable_entity
        end

        return render(json: { campaign: campaign_json(campaign) }) if campaign.update(campaign_attributes)

        render json: { error: campaign.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      private

      # Accepts "123" or "gid://application/campaign/123".
      def find_campaign
        id = params[:id].to_s.split('/').last
        campaign = WhatsappCampaign.find_by(id: id, shop_id: @shop.id)
        render(json: { error: 'Campaign not found.' }, status: :not_found) unless campaign
        campaign
      end

      def campaign_attributes
        attrs = params.permit(:name, :description, :audience_source).to_h
        if params.key?(:whatsapp_template_id)
          template_id = params[:whatsapp_template_id].presence
          attrs[:whatsapp_template_id] = template_id && @shop.whatsapp_templates.where(id: template_id).pick(:id)
        end
        attrs[:scheduled_at] = parse_time(params[:scheduled_at]) if params.key?(:scheduled_at)
        attrs
      end

      # "2026-10-01T10:00" (no offset) is wall-clock in the store's zone, the
      # same convention as the Campaigns page.
      def parse_time(value)
        value.to_s.strip.presence && shop_tz.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def shop_tz
        @shop_tz ||= begin
          name = ScheduledShopReport.extract_iana_from_shop_timezone(@shop.owner_timezone.to_s.strip)
          ActiveSupport::TimeZone[name.to_s] || ActiveSupport::TimeZone['UTC']
        rescue StandardError
          ActiveSupport::TimeZone['UTC']
        end
      end

      def campaign_json(campaign)
        {
          id: campaign.id,
          gid: "gid://application/campaign/#{campaign.id}",
          name: campaign.name,
          description: campaign.description,
          status: campaign.status,
          audience_source: campaign.audience_source,
          whatsapp_template_id: campaign.whatsapp_template_id,
          scheduled_at: campaign.scheduled_at&.in_time_zone(shop_tz)&.strftime('%Y-%m-%dT%H:%M')
        }
      end

      def campaign_link(campaign)
        resource_link(
          type: 'campaign',
          id: campaign.id,
          name: "#{campaign.name} — #{campaign.status}",
          meta: {
            status: campaign.status,
            audience: campaign.audience_source,
            template: campaign.whatsapp_template&.name,
            scheduled_at: campaign.scheduled_at&.in_time_zone(shop_tz)&.iso8601,
            updated_at: campaign.updated_at&.iso8601
          }
        )
      end
    end
  end
end
