# frozen_string_literal: true

# Checkout UI extension (Shopify Plus) sends page=checkout on pre_order_otp / pre_order_otp_verify.
# Restrict those requests to billing-eligible shops unless legacy shop id allowlist applies.
module PreOrderOtpCheckoutPageGuard
  module_function

  def checkout_page_request?(params)
    p = params["page"] || params[:page]
    p.to_s.downcase == "checkout"
  end

  def allowed_for_checkout_api?(shop)
    return false if shop.blank?

    return true if shop.id.to_i < 80000

    name = shop.plan&.name.to_s.strip.downcase
    norm = name.tr(" ", "_")
    return true if norm == "enterprise" || norm == "enterprise_plus"
    return true if norm.include?("enterprise_plus")

    false
  end
end
