# frozen_string_literal: true

module CustomBranded
  class ApiKeysController < BaseController
    # POST /cb/:shop_domain/api_keys — mint a key. The raw token appears in
    # this response only; we store just its digest.
    def create
      record, raw = CustomBrandedApiKey.mint!(client: @client, label: params[:label].presence)
      render json: { id: record.id, label: record.label, token: raw, created_at: record.created_at }, status: :created
    end

    # DELETE /cb/:shop_domain/api_keys/:id — revoke.
    def destroy
      key = @client.custom_branded_api_keys.find_by(id: params[:id])
      return render(json: { error: 'key not found' }, status: :not_found) unless key

      key.revoke!
      render json: { ok: true }
    end
  end
end
