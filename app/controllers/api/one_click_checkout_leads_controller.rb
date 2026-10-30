# frozen_string_literal: true

class Api::OneClickCheckoutLeadsController < AuthenticatedController
  PURPOSE = "one_click_checkout"
  MAX_ORDER_CONFIRMATIONS = 30
  EXCLUDED_SHOPIFY_PLANS = /staff|partner/i

  def eligibility
    render json: {
      eligible: eligible?(@shop),
      already_submitted: already_submitted?(@shop),
      owner_phone: @shop.owner_phone
    }
  end

  def create
    unless eligible?(@shop)
      return render json: { error: "not_eligible" }, status: :forbidden
    end

    if already_submitted?(@shop)
      return render json: { error: "already_submitted" }, status: :unprocessable_entity
    end

    lead = LeadCollection.new(
      email: @shop.owner_email.presence || @shop.customer_email.presence || "unknown@#{@shop.shopify_domain}",
      phone_number: lead_params[:phone_number],
      purpose: PURPOSE,
      preferred_time_to_connect: "Anytime",
      website: @shop.shopify_domain,
      notes: "One-click checkout launch offer (2% -> 0.5%) interest from COD King dashboard. " \
             "Shop: #{@shop.shopify_domain}, owner: #{@shop.shop_owner.presence || @shop.owner_name}, " \
             "shopify_plan: #{@shop.shopify_plan}, installed_at: #{@shop.created_at&.strftime('%Y-%m-%d')}"
    )

    if lead.save
      LeadCollectionMailer.notify_one_click_checkout_interest(lead.id, @shop.id).deliver_later
      render json: { success: true }
    else
      render json: { error: "validation_failed", errors: lead.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  private

  def eligible?(shop)
    return false if shop.blank?
    return false unless shop.country_code == "IN"
    return false if shop.shopify_plan.to_s.match?(EXCLUDED_SHOPIFY_PLANS)
    return false unless shop.created_at.present? && shop.created_at >= 1.month.ago

    shop.order_confirmations.limit(MAX_ORDER_CONFIRMATIONS).count < MAX_ORDER_CONFIRMATIONS
  end

  def paid_subscription?(shop)
    shop.billing_activated? || (shop.plan.present? && shop.plan.name != "Free")
  end

  def already_submitted?(shop)
    LeadCollection.exists?(purpose: PURPOSE, website: shop.shopify_domain)
  end

  def lead_params
    params.require(:one_click_checkout_lead).permit(:phone_number)
  end
end
