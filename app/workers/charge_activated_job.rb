class ChargeActivatedJob < ActiveJob::Base

  def perform(shop_id)
    shop = Shop.find(shop_id)
    client = SlackNotifier::INSTALLS_CLIENT
    client.ping(
      text: ":heart_eyes: *Charge Activated* (#{Rails.env}) <!channel>\n*Store*: ##{shop.primary_domain.presence || shop.shopify_domain}\n*Plan*: #{shop.plan.name}",
      channel: ENV.fetch("SLACK_INSTALLS_CHANNEL", nil)
    )
    CodKingStat.increment_stat('charge_activations')
    CodKingStat.increment_stat("#{shop.plan.name}-activations")

    # Authoritative onboarding funnel "billing_approved" event. Recorded here (not on
    # the client) so it survives device/tab/session changes. Gated on a recent
    # onboarding `billing_started` so dashboard/pricing-page upgrades — which never
    # emit billing_started — are excluded.
    record_onboarding_billing_approved(shop)
    CountryPlanOfferRedemption.activate_for!(shop)

    if shop.charge_id.present?
      # Don't unlock if Shopify capped amount is exhausted. 
      begin
        shop.init_session
        recurring_charge = ShopifyAPI::RecurringApplicationCharge.find(shop.charge_id)
        if recurring_charge&.capped_amount.present? && recurring_charge.balance_remaining.to_f <= 0
          Rails.logger.info "ChargeActivatedJob: skipping unlock for #{shop.shopify_domain} - capped amount exhausted"
          return
        end
      rescue StandardError => e
        Rails.logger.warn "ChargeActivatedJob: could not check capped amount for #{shop.shopify_domain}: #{e.message}"
      end
    end

    attrs = { locked: false }
    attrs[:lock_paid_feature] = false unless shop.plan&.name.to_s.casecmp?('free')

    shop.setting.update(attrs)

    # If branded WhatsApp number is set but current plan is not Enterprise/India Budget/Rabbit, remove it and notify
    plan_name = shop.plan&.name.to_s.downcase
    if shop.setting.branded_whatsapp_number.present? &&
       !plan_name.include?('enterprise') && !plan_name.include?('india_budget') && !plan_name.include?('rabbit')
      previous_number = shop.setting.branded_whatsapp_number
      shop.setting.update(branded_whatsapp_number: '', whatsapp_operator_config: '')
      WelcomeMailer.whatsapp_branding_removed_downgrade(shop.id).deliver_later
      WelcomeMailer.whatsapp_branding_removed_admin_notification(shop.id, previous_number).deliver_later
    end
  end

  private

  # Emit a server-side "billing_approved" onboarding event, but only when this
  # activation originated from the onboarding wizard (i.e. there's a recent
  # billing_started). Dedups against any billing_approved already recorded after
  # that start, so it never double-counts alongside other paths.
  def record_onboarding_billing_approved(shop)
    last_started = shop.onboarding_events
                       .where(event: "billing_started")
                       .where("occurred_at >= ?", 14.days.ago)
                       .order(occurred_at: :desc)
                       .first
    return unless last_started

    already_approved = shop.onboarding_events
                           .where(event: "billing_approved")
                           .where("occurred_at >= ?", last_started.occurred_at)
                           .exists?
    return if already_approved

    shop.onboarding_events.create!(
      event: "billing_approved",
      step: 4,
      feature: "quick-onboarding-v2",
      # Record the activated plan so "approved billing by plan" survives uninstall
      # (read from metadata instead of joining the shop, which may be gone).
      metadata: { "plan" => shop.plan&.name },
      occurred_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn "ChargeActivatedJob: could not record billing_approved for #{shop.shopify_domain}: #{e.message}"
  end
end
