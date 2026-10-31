# frozen_string_literal: true

module Api
  module V1
    module Cb
      # Brand lifecycle — partner key only.
      # POST registers (or finds) a brand and returns SIGNED portal URLs, so
      # ParcelX's server can 302 the merchant's browser straight to the
      # connect page without implementing the HMAC link-signing itself.
      # GET lists/queries brands with connection + usage summary.
      class BrandsController < BaseController
        skip_before_action :require_client!
        before_action :require_partner!

        LINK_TTL = 7.days

        # GET /api/v1/cb/brands            — all brands
        # GET /api/v1/cb/brands?shop_domain=x.com — just that brand
        def index
          scope = CustomBrandedClient.order(:domain)
          domain = CustomBrandedClient.normalize_domain(params[:shop_domain])
          scope = scope.where(domain: domain) if domain.present?

          render json: { brands: scope.map { |c| serialize(c) } }
        end

        # POST /api/v1/cb/brands { shop_domain, label? }
        def create
          client = CustomBranded::ClientProvisioner.call(domain: params[:shop_domain])
          client.update(label: params[:label]) if params[:label].present?

          exp = LINK_TTL.from_now.to_i
          render json: serialize(client).merge(
            connect_url: signed_url(client, exp, '/connect'),
            portal_url: signed_url(client, exp, ''),
            links_expire_at: Time.at(exp).utc.iso8601
          ), status: :created
        rescue CustomBranded::ClientProvisioner::InvalidDomain => e
          render_error(e.message, :unprocessable_entity)
        end

        private

        def require_partner!
          return if partner_authenticated?

          render_error('brand endpoints require the partner API key', :forbidden)
        end

        def serialize(c)
          accounts = c.whatsapp_accounts.to_a
          {
            shop_domain: c.domain,
            label: c.label,
            numbers_connected: accounts.size,
            numbers_ready: accounts.count(&:ready_to_send?),
            templates_total: c.whatsapp_templates.count,
            templates_approved: c.whatsapp_templates.approved.count,
            messages_total: c.whatsapp_message_logs.count,
            created_at: c.created_at,
            last_portal_access_at: c.last_portal_access_at
          }
        end

        def signed_url(client, exp, suffix)
          sig = OpenSSL::HMAC.hexdigest('SHA256', ENV.fetch("CB_PARTNER_SIGNING_SECRET", nil).to_s, "#{client.domain}|#{exp}")
          "https://#{ENV.fetch("APP_HOST", nil)}/cb/#{client.domain}#{suffix}?exp=#{exp}&sig=#{sig}"
        end
      end
    end
  end
end
