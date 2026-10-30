# frozen_string_literal: true

module ShopifyServices
  # Read-only lookup of a shop's active recurring application charge (its COD
  # King subscription). Companion to UsageChargeApplyService. Never raises for
  # expected failures.
  #
  #   ShopifyServices::ActiveSubscriptionService.call('store.myshopify.com')
  #   # => { success: true, active: true, reason: nil, shop: {...},
  #   #      subscription: { plan_name: 'Pro', price: 19.99, currency: 'USD', ... } }
  #
  # Reasons (result[:reason]):
  #   shop_not_found          — no Shop row for the supplied domain (success: false)
  #   shop_unauthorized       — offline token rejected, app likely uninstalled (success: false)
  #   no_active_subscription  — no charge_id, or Shopify charge is not active (success: true, active: false)
  class ActiveSubscriptionService < ApplicationService
    attr_reader :domain

    def initialize(domain)
      @domain = UsageChargeApplyService.normalize_domain(domain)
    end

    def call
      return failure(:shop_not_found) if domain.blank?

      shop = Shop.find_by(shopify_domain: domain)
      return failure(:shop_not_found) if shop.nil?
      return inactive(shop) if shop.charge_id.blank?

      shop.init_session
      recurring = load_recurring_charge(shop)
      return failure(:shop_unauthorized, shop: shop) if recurring == :unauthorized
      return inactive(shop, recurring) if recurring.nil? || recurring.status.to_s != 'active'

      {
        success: true,
        active: true,
        reason: nil,
        shop: shop_payload(shop),
        subscription: subscription_payload(recurring)
      }
    end

    private

    def load_recurring_charge(shop)
      ShopifyAPI::RecurringApplicationCharge.find(shop.charge_id)
    rescue ActiveResource::ResourceNotFound
      nil
    rescue ActiveResource::UnauthorizedAccess, ActiveResource::ForbiddenAccess
      :unauthorized
    end

    def subscription_payload(recurring)
      {
        id: recurring.id,
        plan_name: recurring.name,
        status: recurring.status,
        price: safe_float(recurring.price),
        currency: attr(recurring, :currency) || 'USD',
        capped_amount: safe_float(attr(recurring, :capped_amount)),
        balance_used: safe_float(attr(recurring, :balance_used)),
        balance_remaining: safe_float(attr(recurring, :balance_remaining)),
        terms: attr(recurring, :terms),
        test: attr(recurring, :test),
        billing_on: attr(recurring, :billing_on),
        trial_ends_on: attr(recurring, :trial_ends_on),
        activated_on: attr(recurring, :activated_on)
      }
    end

    def inactive(shop, recurring = nil)
      {
        success: true,
        active: false,
        reason: 'no_active_subscription',
        shop: shop_payload(shop),
        subscription: nil,
        last_known_status: recurring.respond_to?(:status) ? recurring.status : nil
      }.compact
    end

    def shop_payload(shop)
      { id: shop.id, shopify_domain: shop.shopify_domain, plan: shop.plan&.name }
    end

    def failure(reason, shop: nil)
      {
        success: false,
        active: false,
        reason: reason.to_s,
        shop: (shop ? shop_payload(shop) : nil),
        subscription: nil
      }.compact
    end

    def attr(record, name)
      record.respond_to?(name) ? record.public_send(name) : nil
    end

    def safe_float(value)
      return nil if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
