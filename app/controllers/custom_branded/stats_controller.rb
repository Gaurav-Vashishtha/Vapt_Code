# frozen_string_literal: true

module CustomBranded
  # ParcelX operations panel at /cb-stats — tabs: stats, webhooks, keys, docs.
  # PUBLIC (no auth) by explicit product decision "for now": it renders
  # aggregate counts, message/webhook metadata and API documentation — never
  # message content bodies, tokens, or keys. Key management on the keys tab
  # calls the partner-key-protected /api/v1/cb/keys endpoints from the
  # browser (ParcelX staff paste the partner key; it stays in sessionStorage).
  # Gate the whole page behind partner auth before wider rollout.
  class StatsController < ApplicationController
    # Embeddable in the ParcelX dashboard iframe (drops X-Frame-Options).
    include CustomBranded::PartnerEmbeddable

    layout false
    skip_before_action :verify_authenticity_token

    before_action :ensure_enabled!

    TABS = %w[stats webhooks keys docs].freeze

    def show
      @brand_logo = ENV['CB_BRAND'].presence
      @brand_name = ENV['CB_BRAND_NAME'].presence || 'ParcelX WhatsApp Automation Panel'
      @tab = TABS.include?(params[:tab]) ? params[:tab] : 'stats'

      @clients = CustomBrandedClient.order(:domain)
      @brand = params[:brand].presence && @clients.find { |c| c.domain == params[:brand] }

      case @tab
      when 'stats'    then load_stats
      when 'webhooks' then load_webhooks
      end
    end

    # GET /cb-docs/openapi.json — the OpenAPI spec Swagger UI renders on the
    # docs tab. Built per request so `servers` matches the current host.
    def openapi
      render json: CustomBranded::OpenapiSpec.build(request.base_url)
    end

    private

    def load_stats
      scope = WhatsappMessageLog.where.not(custom_branded_client_id: nil)
      scope = scope.where(custom_branded_client_id: @brand.id) if @brand

      @totals = scope.group(:status).count
      @last_30d = scope.where('created_at >= ?', 30.days.ago).group(:status).count

      unless @brand
        raw = WhatsappMessageLog.where.not(custom_branded_client_id: nil)
                                .group(:custom_branded_client_id, :status).count
        @per_brand = Hash.new { |h, k| h[k] = {} }
        raw.each { |(client_id, status), count| @per_brand[client_id][status] = count }
      end

      @recent = scope.recent.limit(50)
    end

    def load_webhooks
      @webhook_forward_url = ENV['CB_WEBHOOK_FORWARD_URL'].presence
      @webhook_secret_set = ENV['CB_WEBHOOK_FORWARD_SECRET'].present?
      @webhook_deliveries =
        if ActiveRecord::Base.connection.table_exists?(:custom_branded_webhook_deliveries)
          scope = CustomBrandedWebhookDelivery.recent
          scope = scope.where(custom_branded_client_id: @brand.id) if @brand
          scope.limit(50)
        else
          []
        end
      @clients_by_id = @clients.index_by(&:id)
    end

    def ensure_enabled!
      return if ActiveModel::Type::Boolean.new.cast(ENV['CB_PORTAL_ENABLED'])

      head :not_found
    end
  end
end
