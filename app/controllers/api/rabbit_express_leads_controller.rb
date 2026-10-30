# frozen_string_literal: true

class Api::RabbitExpressLeadsController < AuthenticatedController
  PURPOSE = "rabbit_express"
  EXCLUDED_SHOPIFY_PLANS = /staff|partner|dev|affiliate|sandbox/i

  def eligibility
    render json: {
      eligible: eligible?(@shop),
      already_submitted: already_submitted?(@shop),
      owner_phone: @shop.owner_phone,
      owner_email: default_email(@shop)
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
      email: lead_params[:email].presence || default_email(@shop),
      phone_number: lead_params[:phone_number],
      purpose: PURPOSE,
      preferred_time_to_connect: "Anytime",
      website: @shop.shopify_domain,
      notes: "Rabbit Express shipping launch-offer interest from COD King dashboard. " \
             "Shop: #{@shop.shopify_domain}, owner: #{@shop.shop_owner.presence || @shop.owner_name}, " \
             "shopify_plan: #{@shop.shopify_plan}, installed_at: #{@shop.created_at&.strftime('%Y-%m-%d')}"
    )

    if lead.save
      LeadCollectionMailer.notify_rabbit_express_interest(lead.id, @shop.id).deliver_later
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

    !shop.shopify_plan.to_s.match?(EXCLUDED_SHOPIFY_PLANS)
  end

  def already_submitted?(shop)
    LeadCollection.exists?(purpose: PURPOSE, website: shop.shopify_domain)
  end

  def default_email(shop)
    shop.owner_email.presence || shop.customer_email.presence || "unknown@#{shop.shopify_domain}"
  end

  def lead_params
    params.require(:rabbit_express_lead).permit(:phone_number, :email)
  end
end
