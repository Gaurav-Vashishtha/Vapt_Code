# frozen_string_literal: true

class ExistingCustomersController < ApiController
  # POST /is-existing-customer
  #
  # Body: shopify_domain (or shop), phone (with country code), email (optional)
  # Called by the popup right after the OTP is sent.
  def show
    payload = params.to_unsafe_h
    domain = payload["shopify_domain"].presence || payload["shop"].presence
    shop = domain.present? ? Shop.find_by(shopify_domain: domain) : nil
    return render(json: { status: "Error", message: "Shop not found" }, status: :not_found) if shop.blank?

    unless PartialRuleSet.existing_customer_check_needed?(shop)
      return render(json: { existing: false, orders_count: 0, last_order_date: nil })
    end

    result = ExistingCustomerService.call(shop, phone: payload["phone"], email: payload["email"])
    render json: result.slice(:existing, :orders_count, :last_order_date)
  end
end
