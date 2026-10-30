# frozen_string_literal: true

module ShopifyServices
  # Applies a one-off usage charge against a shop's active recurring
  # application charge and reports the subscription state alongside the
  # outcome. Pure result object — never raises for expected failures.
  #
  #   ShopifyServices::UsageChargeApplyService.call('store.myshopify.com', 12.5)
  #   # => { success: true, reason: nil, subscription: {...}, usage_charge: {...} }
  #
  # Failure reasons (result[:reason]):
  #   shop_not_found            — no Shop row for the supplied domain
  #   no_active_subscription    — no charge_id, or Shopify charge is not active
  #   capped_amount_exhausted   — charge exceeds the remaining capped balance
  #   invalid_charge            — charge is not a positive number
  #   shop_unauthorized         — offline token rejected (app likely uninstalled)
  #   charge_failed             — Shopify rejected the usage charge for another reason
  class UsageChargeApplyService < ApplicationService
    DEFAULT_DESCRIPTION = 'COD-King-Charges'
    CAP_ERROR_PATTERN = /capped|balance|exceed/i

    attr_reader :domain, :charge, :description

    def initialize(domain, charge, description: nil)
      @domain = self.class.normalize_domain(domain)
      @charge = charge
      @description = description.presence || DEFAULT_DESCRIPTION
    end

    def self.normalize_domain(raw)
      d = raw.to_s.strip.downcase
      d = d.sub(%r{\Ahttps?://}, '').split('/').first.to_s
      d = "#{d}.myshopify.com" if d.present? && !d.include?('.')
      d
    end

    def call
      return failure(:shop_not_found) if domain.blank?

      shop = Shop.find_by(shopify_domain: domain)
      return failure(:shop_not_found) if shop.nil?

      amount = parse_amount(charge)
      return failure(:invalid_charge, shop: shop) if amount.nil?

      return failure(:no_active_subscription, shop: shop) if shop.charge_id.blank?

      shop.init_session
      recurring = load_recurring_charge(shop)
      return failure(:shop_unauthorized, shop: shop) if recurring == :unauthorized
      return failure(:no_active_subscription, shop: shop) if recurring.nil? || recurring.status.to_s != 'active'

      subscription = subscription_payload(recurring)
      remaining = subscription[:balance_remaining]
      if remaining && amount > remaining
        return failure(:capped_amount_exhausted, shop: shop, subscription: subscription)
      end

      apply_usage_charge(shop, recurring, amount, subscription)
    end

    private

    def parse_amount(raw)
      value = Float(raw.to_s.strip)
      return nil unless value.finite? && value.positive?

      value.round(2)
    rescue ArgumentError, TypeError
      nil
    end

    def load_recurring_charge(shop)
      ShopifyAPI::RecurringApplicationCharge.find(shop.charge_id)
    rescue ActiveResource::ResourceNotFound
      nil
    rescue ActiveResource::UnauthorizedAccess, ActiveResource::ForbiddenAccess
      :unauthorized
    end

    def apply_usage_charge(shop, recurring, amount, subscription)
      usage_charge = ShopifyAPI::UsageCharge.new(
        recurring_application_charge_id: shop.charge_id,
        usage_charge: { description: description, price: amount }
      )

      if usage_charge.save
        Rails.logger.info("[UsageChargeApply] shop=#{shop.shopify_domain} charge=#{amount} usage_charge_id=#{usage_charge.id} remaining=#{usage_charge.balance_remaining}")
        after = subscription.merge(
          balance_used: safe_float(usage_charge.balance_used) || subscription[:balance_used],
          balance_remaining: safe_float(usage_charge.balance_remaining) || subscription[:balance_remaining]
        )
        shop.update(risk_level: usage_charge.risk_level) if usage_charge.respond_to?(:risk_level) && usage_charge.risk_level.present?
        {
          success: true,
          reason: nil,
          shop: shop_payload(shop),
          subscription: after,
          usage_charge: {
            id: usage_charge.id,
            description: description,
            price: amount,
            currency: subscription[:currency],
            created_at: (usage_charge.respond_to?(:created_at) ? usage_charge.created_at : nil)
          }
        }
      else
        messages = Array(usage_charge.errors&.full_messages).join('; ').presence
        reason = messages.to_s.match?(CAP_ERROR_PATTERN) ? :capped_amount_exhausted : :charge_failed
        failure(reason, shop: shop, subscription: subscription, detail: messages)
      end
    rescue ActiveResource::UnauthorizedAccess, ActiveResource::ForbiddenAccess
      failure(:shop_unauthorized, shop: shop, subscription: subscription)
    rescue ActiveResource::ClientError => e
      body = e.response&.body.to_s
      reason = body.match?(CAP_ERROR_PATTERN) ? :capped_amount_exhausted : :charge_failed
      failure(reason, shop: shop, subscription: subscription, detail: body.presence || e.message)
    end

    def subscription_payload(recurring)
      {
        id: recurring.id,
        name: recurring.name,
        status: recurring.status,
        price: safe_float(recurring.price),
        capped_amount: safe_float(recurring.capped_amount),
        balance_used: safe_float(recurring.balance_used),
        balance_remaining: safe_float(recurring.balance_remaining),
        currency: (recurring.respond_to?(:currency) ? recurring.currency : nil),
        terms: (recurring.respond_to?(:terms) ? recurring.terms : nil),
        billing_on: (recurring.respond_to?(:billing_on) ? recurring.billing_on : nil),
        trial_ends_on: (recurring.respond_to?(:trial_ends_on) ? recurring.trial_ends_on : nil),
        activated_on: (recurring.respond_to?(:activated_on) ? recurring.activated_on : nil)
      }
    end

    def shop_payload(shop)
      { id: shop.id, shopify_domain: shop.shopify_domain, plan: shop.plan&.name }
    end

    def failure(reason, shop: nil, subscription: nil, detail: nil)
      {
        success: false,
        reason: reason.to_s,
        shop: (shop ? shop_payload(shop) : nil),
        subscription: subscription,
        usage_charge: nil,
        detail: detail
      }.compact
    end

    def safe_float(value)
      return nil if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
