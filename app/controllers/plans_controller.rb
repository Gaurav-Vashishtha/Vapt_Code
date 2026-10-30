class PlansController < AuthenticatedController
  before_action :set_shop

  # Plans whose name contains one of these keywords include WhatsApp BSP
  # notifications. Switching away from them while a notification is live is
  # blocked (see whatsapp_notifications_block_change?).
  WHATSAPP_PLAN_KEYWORDS = %w[enterprise india_budget].freeze

  WHATSAPP_DOWNGRADE_BLOCKED_MESSAGE =
    "Turn off your WhatsApp notifications before switching to this plan — it " \
    "doesn't include WhatsApp notifications and you currently have at least " \
    "one turned on. Go to WhatsApp → Notifications and turn them off, then try again.".freeze

  # GET /plans/india_pricing — returns dynamic pricing for India plans (Pro, india_budget) for current shop.
  # Uses shop_created_date and current subscription; optionally reads Shopify recurring charge for actual amount.
  def india_pricing
    return head :bad_request unless @shop
    pricing = IndiaPlanPricingService.new(@shop)
    fetch_shopify = params[:fetch_shopify].to_s == "true"
    plans = pricing.all_display_pricing(fetch_shopify_charge: fetch_shopify)
    v3 = PricingV3India.applies_to_shop?(@shop)
    render json: {
      plans: plans,
      pricing_version: v3 ? "v3" : "v2",
      message_rates: v3 ? v3_message_rates : nil,
      free_message_rates: v3 ? free_plan_message_rates : nil,
      partial_payment_rates: v3 ? partial_payment_rates : nil,
      # Array (not a hash keyed by plan name) so the client's camelizeKeys leaves plan names intact.
      country_offers: CountryPlanOffer.display_for(@shop).map { |plan_name, offer| offer.merge("plan_name" => plan_name) }
    }
  end

  # GET /plans/otp_campaign — free pre-order OTP campaign status for the
  # subscription page (window, whether this shop already redeemed).
  def otp_campaign
    return head :bad_request unless @shop
    render json: PreOrderOtpCampaign.status_for(@shop)
  end

  # POST /plans/apply_otp_campaign_coupon — redeem the ENV-configured coupon.
  # Eligibility (install window, no uninstall after start) is enforced in
  # PreOrderOtpCampaign.
  def apply_otp_campaign_coupon
    return head :bad_request unless @shop

    error = PreOrderOtpCampaign.apply!(@shop, params[:code])
    if error
      render json: { error: error }, status: :unprocessable_entity
    else
      SlackNotifyJob.perform_async(
        ":tada: OTP campaign coupon applied (#{Rails.env})\n Store: #{@shop.shopify_domain}"
      ) rescue nil
      render json: PreOrderOtpCampaign.status_for(@shop)
    end
  end

  # DELETE /plans/remove_otp_campaign_coupon — un-apply the coupon.
  def remove_otp_campaign_coupon
    return head :bad_request unless @shop

    PreOrderOtpCampaign.remove!(@shop)
    render json: PreOrderOtpCampaign.status_for(@shop)
  end

  def upgrade
    plan = Plan.find_by(name: params['name'])
    return render json: { error: "Plan not found" }, status: :not_found unless plan

    if whatsapp_notifications_block_change?(plan)
      return render json: { error: WHATSAPP_DOWNGRADE_BLOCKED_MESSAGE }, status: :unprocessable_entity
    end

    record_onboarding_plan_selected(plan)

    price = if IndiaPlanPricingService::INDIA_PLANS.include?(plan.name)
              IndiaPlanPricingService.new(@shop).charge_price_usd(plan.name)
            end
    charge_price = price.present? ? price.to_f : plan.price.to_f
    charge_price = SubscriptionOffer::CHARGE_USD if plan.price.to_f.positive? && SubscriptionOffer.eligible?(@shop)
    # Country offer (admin: /admin/country_plan_offers) wins over the global promo.
    country_offer = plan.price.to_f.positive? ? CountryPlanOffer.for(@shop, plan.name) : nil
    charge_price = country_offer.price_usd.to_f if country_offer&.price_usd
    trial_days = country_offer&.trial_days.to_i

    return_url = "https://#{@shop.shopify_domain}/admin/apps/cod-verification/custom_setup?plan_id=#{plan.id}"
    if (Rails.env.development?)
      return_url = "https://#{@shop.shopify_domain}/admin/apps/codkingamandev/custom_setup?plan_id=#{plan.id}"
    end

    recurring_charge = ShopifyAPI::RecurringApplicationCharge.new(
      name: plan.name,
      price: charge_price,
      return_url: return_url,
      test: Rails.env.development?,
      trial_days: trial_days,
    )
    
    usa_price = TwilioPricing.find_by(country_code: 'US').sms_price.to_f
    # The capped amount is shown to the merchant on Shopify's charge-approval
    # screen as "may charge up to $X". $300 reads as scary sticker shock for
    # Indian stores (~₹25k) — and Indian SMS/WhatsApp rates are low, so a $100
    # cap is plenty of headroom. Lower default for India to reduce abandonment.
    default_cap = @shop.country_code == 'IN' ? 300 : 300
    capped_amt = params['capped_amount'] || default_cap
    recurring_charge.capped_amount = capped_amt
    terms = "Dont worry - We wont charge anything for test SMS and charge for the number of SMS sent. For e.g if you are sending 100 SMS in United states, we will only charge $#{usa_price * 100} . SMS charges vary country to country. Please check latest SMS pricing on https://cod.birdchime.com/pricing. You can also reach out to us for custom SMS provider integration or bulk pricing."
    terms = v3_charge_terms if plan.price.to_f.positive? && PricingV3India.applies_to_shop?(@shop)
    recurring_charge.terms = terms
    
    if recurring_charge.save
      CountryPlanOfferRedemption.record_pending!(country_offer, @shop, recurring_charge.id) if country_offer
      client = Slack::Notifier.new  'https://hooks.slack.com/services/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'
      client.ping(
        text: "*Charge Initiated* \n Store: #{@shop.primary_domain.presence || @shop.shopify_domain} \n Plan: #{plan.name} \n Amount: #{charge_price} \n Capped Amount: #{capped_amt} #{country_offer ? "\n Offer: #{country_offer.name} (trial #{trial_days} days)" : ''}",
        channel: ENV['SLACK_INSTALLS_CHANNEL']
      )
      @shop.update({
        max_orders: params[:orders]
      })
      if plan.name == 'Free'
        @shop.setting.update({
          provider: '',
          provider_api_key: '',
          provider_sender_id: '',
        })
      end
      render json: {
        confirmation_url: recurring_charge.confirmation_url,
        shop: current_shopify_domain
      }
    end
  end

  def cancel
    # add cancel checks
    # Cancelling drops the shop to Free, which has no WhatsApp notifications —
    # block it the same way as a downgrade while any notification is live.
    # Allowlisted shops keep WhatsApp regardless of plan, so they're exempt.
    if @shop.whatsapp_notifications_active? && !@shop.whatsapp_bsp_plan_exempt?
      return render json: { error: WHATSAPP_DOWNGRADE_BLOCKED_MESSAGE }, status: :unprocessable_entity
    end

    recurring_application_charge = ShopifyAPI::RecurringApplicationCharge.current
    puts "recurring_application_charge.present......... : #{recurring_application_charge.present?}"
    if recurring_application_charge.present?
      recurring_application_charge.destroy
    end
    plan = Plan.find_by(name: 'Free')
    SlackNotifyJob.perform_async(
      ":rage:  Charge Cancelled (#{Rails.env})\n  Store: #{@shop.shopify_domain} \n Plan: #{@shop.plan.name}"
    )
    CodKingStat.increment_stat('charge_cancellations')
    CodKingStat.increment_stat("#{@shop.plan.name}-deactivations")
    
    @shop.update(plan_id: plan.id, charge_id: '')
    @shop.setting.update(sms: false, ivr: false, status: false)
    
    render json: @shop.plan
  end

  def update_capped_amount
    @recurring_application_charge = ShopifyAPI::RecurringApplicationCharge.current

    if @recurring_application_charge.customize({capped_amount: params[:capped_amount]})
      render json: {
        confirmation_url: recurring_charge.update_capped_amount_url,
        shop: current_shopify_domain
      }
    else
      render json: @recurring_application_charge.errors.messages
    end
  end

  def usage_charge
    @recurring_application_charge = ShopifyAPI::RecurringApplicationCharge.current
    @usage_charges = @recurring_application_charge.usage_charges if @recurring_application_charge.try(:capped_amount)
    render json: @usage_charges
    
    # render json: @shop.usage_charges
    # payload = {"description": "Test 1", "price": 1}
    # usage_charge = ShopifyAPI::UsageCharge.new(payload)
    # usage_charge.prefix_options[:recurring_application_charge_id] = ShopifyAPI::RecurringApplicationCharge.current.id
    # usage_charge.save

    # @recurring_application_charge = ShopifyAPI::RecurringApplicationCharge.current
    # @usage_charges = @recurring_application_charge.usage_charges if @recurring_application_charge.try(:capped_amount)
  end

  # GET /plans/opted_plan
  # GET /plans/opted_plan.json
  def opted_plan
    render json: @shop.plan
  end

  private

  def v3_message_rates
    rates = PricingV3India.display_rates
    {
      sms: rates[:sms],
      whatsapp_utility: rates[:whatsapp_utility],
      whatsapp_marketing: rates[:whatsapp_marketing],
      bsp_whatsapp: bsp_whatsapp_inr_display
    }
  end

  # Branded WhatsApp (merchant's own number) commission, shown in INR on the India plans.
  def bsp_whatsapp_inr_display
    PricingV3India.format_inr(MessagePricing::BSP_WHATSAPP_USD * PricingV3India.inr_per_usd)
  end

  def free_plan_message_rates
    PricingV3India.display_rates(PricingV3India::FREE_RATES_INR)
  end

  def partial_payment_rates
    {
      free: format_percent(PartialTransactionFee.free_rate(@shop)),
      pro: format_percent(PartialTransactionFee::PRO),
      enterprise: format_percent(PartialTransactionFee::ENTERPRISE),
      enterprise_plus: format_percent(PartialTransactionFee::ENTERPRISE_PLUS)
    }
  end

  def format_percent(rate)
    value = rate * 100
    formatted = value == value.to_i ? value.to_i.to_s : value.to_s
    "#{formatted}%"
  end

  def v3_charge_terms
    rates = PricingV3India.display_rates
    "Usage-based. You are charged per message sent: SMS #{rates[:sms]}, WhatsApp utility #{rates[:whatsapp_utility]}, WhatsApp marketing #{rates[:whatsapp_marketing]}; WhatsApp from your own number (Enterprise plans) #{bsp_whatsapp_inr_display}, Meta's own fees billed to you directly. Test messages are free. Amounts are billed in USD at #{PricingV3India.inr_per_usd.round(2)} INR per USD. Details: https://notifiktech.com/message-pricing"
  end

  # True when moving to `target_plan` would drop WhatsApp notifications while the
  # shop still has one live — i.e. the target plan doesn't support WhatsApp and
  # the shop currently has an active account + binding.
  def whatsapp_notifications_block_change?(target_plan)
    # Allowlisted shops keep WhatsApp regardless of plan, so never block them.
    return false if @shop.whatsapp_bsp_plan_exempt?
    !plan_supports_whatsapp?(target_plan) && @shop.whatsapp_notifications_active?
  end

  def plan_supports_whatsapp?(plan)
    name = plan&.name.to_s.downcase
    WHATSAPP_PLAN_KEYWORDS.any? { |kw| name.include?(kw) }
  end

  # Funnel stage: which plan the merchant selected. Recorded only for
  # onboarding-originated upgrades (a recent billing_started), mirroring how
  # billing_approved is gated, so the funnel stays onboarding-scoped.
  def record_onboarding_plan_selected(plan)
    last_started = @shop.onboarding_events
                       .where(event: "billing_started")
                       .where("occurred_at >= ?", 14.days.ago)
                       .order(occurred_at: :desc)
                       .first
    return unless last_started

    @shop.onboarding_events.create!(
      event: "plan_selected",
      feature: "quick-onboarding-v2",
      metadata: { "plan" => plan.name },
      occurred_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("[PlansController] could not record plan_selected for #{@shop.shopify_domain}: #{e.class}: #{e.message}")
  end
end