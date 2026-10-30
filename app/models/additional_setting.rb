# frozen_string_literal: true

# Per-shop settings support adds from /admin/additional_settings, kept out of the settings table.
# third_party_payment_method_rules:
#   {"hide_on_partial": "Snapmint", "hide_on_prepaid": "Snapmint, Simpl"}
# => comma-separated payment method names the checkout payment function hides on part-payment
# (hide_on_partial) or full-prepaid (hide_on_prepaid) orders.
# whatsapp_language_selected: the merchant picked their WhatsApp message language themselves, so the
#   onboarding country default (Whatsapp::TemplateLanguage.suggested_for) is never applied over it.
# pre_order_otp_draft_orders: abandoned pre-order OTP carts (OTP-verified) become Shopify draft
#   orders, one per cart session — see PreOrderOtpDraftJobs::SyncJob.
class AdditionalSetting < ApplicationRecord
  PAYMENT_METHOD_RULE_KEYS = %w[hide_on_partial hide_on_prepaid].freeze

  belongs_to :shop, optional: true

  validates :shop_id, presence: true, uniqueness: true
  validate :shop_exists
  validate :payment_method_rules_shape

  after_commit :sync_storefront_settings, on: %i[create update], if: -> { saved_change_to_upsell_config? || saved_change_to_free_gift_config? }
  after_commit :sync_free_gift_function, on: %i[create update], if: :saved_change_to_free_gift_config?

  def shop_domain
    shop&.shopify_domain
  end

  def self.pre_order_otp_draft_orders?(shop_id)
    where(shop_id: shop_id, pre_order_otp_draft_orders: true).exists?
  end

  def third_party_hidden_payment_methods(key)
    rules = third_party_payment_method_rules
    return "" unless rules.is_a?(Hash)

    Array(rules[key.to_s]).flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:empty?).uniq.join(",")
  end

  private

  def sync_storefront_settings
    shop&.setting&.touch_shop_and_sync_metafields
  end

  def sync_free_gift_function
    ShopifyJobs::FreeGiftFunctionConfigJob.perform_async(shop_id) if shop_id
  end

  def shop_exists
    return if shop_id.blank?

    errors.add(:shop_id, "does not match any shop") unless Shop.exists?(id: shop_id)
  end

  def payment_method_rules_shape
    rules = third_party_payment_method_rules
    unless rules.is_a?(Hash)
      errors.add(:third_party_payment_method_rules, 'must be a JSON object like {"hide_on_partial": "Snapmint", "hide_on_prepaid": ""}')
      return
    end

    unknown = rules.keys.map(&:to_s) - PAYMENT_METHOD_RULE_KEYS
    errors.add(:third_party_payment_method_rules, "has unknown keys: #{unknown.join(', ')} (allowed: #{PAYMENT_METHOD_RULE_KEYS.join(', ')})") if unknown.any?
  end
end
