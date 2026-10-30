# frozen_string_literal: true

# Enforces ShippingApi::OriginValidator before public shipping helpers
# (count + addresses by phone). See ENV["SHIPPING_API_ALLOWED_ORIGINS"].
module ShippingPublicApiOrigin
  extend ActiveSupport::Concern

  private

  def verify_shipping_public_api_origin!
    return if ShippingApi::OriginValidator.permitted?(request)

    render json: { error: true, message: "Origin not allowed" }, status: :forbidden
  end
end
