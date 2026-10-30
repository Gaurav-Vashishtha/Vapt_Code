# frozen_string_literal: true

module Api
  module V1
    module Cb
      # Per-brand API key management — PARTNER KEY ONLY. Keys are minted by
      # the ParcelX team (from the cb-stats panel or server-side), never by
      # merchants. The raw key appears exactly once, in the create response.
      class KeysController < BaseController
        before_action :require_partner!

        # GET /api/v1/cb/keys?shop_domain=...
        def index
          keys = client.custom_branded_api_keys.order(created_at: :desc)
          render json: { shop_domain: client.domain, keys: keys.map { |k| serialize(k) } }
        end

        # POST /api/v1/cb/keys { shop_domain, label? }
        def create
          record, raw = CustomBrandedApiKey.mint!(client: client, label: params[:label].presence)
          render json: serialize(record).merge(key: raw), status: :created
        end

        # DELETE /api/v1/cb/keys/:id?shop_domain=...
        def destroy
          key = client.custom_branded_api_keys.find_by(id: params[:id])
          return render_error('key not found', :not_found) if key.nil?

          key.revoke!
          render json: { ok: true }
        end

        private

        def require_partner!
          return if partner_authenticated?

          render_error('key management requires the partner API key', :forbidden)
        end

        def serialize(k)
          {
            key_id: k.id,
            label: k.label,
            masked: k.masked,
            revoked: k.revoked?,
            created_at: k.created_at,
            last_used_at: k.last_used_at
          }
        end
      end
    end
  end
end
