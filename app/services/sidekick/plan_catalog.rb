# frozen_string_literal: true

module Sidekick
  # What each COD King plan costs and unlocks, for the Shopify Sidekick tools.
  #
  # Mirrors the merchant-facing sources — keep in sync when plans change:
  # - plan cards: app/javascript/packs/Components/Plans.jsx (USD) and PlansIndia.jsx (INR)
  # - INR prices: IndiaPlanPricingService::PRICING
  # - partial payment fees: PartialTransactionFee
  # - minimum tier per gated feature: app/javascript/packs/utils/paidPlanDowngradeBlockers.js
  #   and the plan checks in the feature screens (PreOrderSetting, NetworkSettingTab,
  #   NotificationSettingsTab, WhatsappEventMappings, CODShowHide, CODFeesSettings*)
  module PlanCatalog
    TIERS = %w[free pro enterprise enterprise_plus].freeze

    PLANS = [
      {
        tier: 'free', name: 'Free', usd: 0, inr: 0, message_rate_discount: '0%',
        partial_payment_fee: '1.5% (some older stores keep 1.05%)',
        highlights: ['OTP verification by SMS/WhatsApp', 'Order confirmation, fulfilment and abandoned cart messages',
                     'Partial payments', 'COD to prepaid incentives', 'Basic support']
      },
      {
        tier: 'pro', name: 'Pro', usd: 9.99, inr: 899, message_rate_discount: '15% off SMS, 20% off WhatsApp (COD King number; outside India)',
        partial_payment_fee: '0.8%',
        highlights: ['Everything in Free', 'Limit COD (show/hide COD rules)', 'COD fees', 'Prepaid discount',
                     'Address autofill', 'SMS template approvals', 'Priority support']
      },
      {
        tier: 'enterprise', name: 'Enterprise', usd: 39, inr: 1999, message_rate_discount: '30% off SMS, 40% off WhatsApp (COD King number; outside India)',
        partial_payment_fee: '0.5%',
        highlights: ['Everything in Pro', 'Business Brand WhatsApp from your own number (Meta bills its fees directly; service messages are free)',
                     'OnePass verification', 'Local SMS gateway / branded SMS sender ID', 'WhatsApp chat widget',
                     'Exportable cart and customer data', 'Advanced analytics', 'Dedicated account manager']
      },
      {
        tier: 'enterprise_plus', name: 'Enterprise Plus', usd: 59, inr: 4999, message_rate_discount: '70% off SMS, 40% off WhatsApp (COD King number; outside India)',
        partial_payment_fee: '0%',
        highlights: ['Everything in Enterprise', 'Remove COD King branding',
                     'OTP verification on the Shopify checkout page (Shopify Plus stores)', 'Dedicated account manager']
      }
    ].freeze

    # feature key => [label, minimum tier, where to change it, note]
    FEATURES = {
      'otp_verification' => ['OTP verification (pre-order / post-order)', 'free', '/features/otp/pre-order', nil],
      'customer_notifications' => ['Order confirmation, fulfilment and abandoned cart SMS/WhatsApp', 'free', '/features/notifications', nil],
      'partial_payment' => ['Partial payments (advance on COD)', 'free', '/features/partial-payment', 'Transaction fee depends on plan'],
      'cod_to_prepaid' => ['COD to prepaid conversion', 'free', '/features/cod-to-prepaid', '2% fee on converted orders; India stores'],
      'whatsapp_cod_verification' => ['WhatsApp COD verification', 'free', '/features/whatsapp-cod-verification', nil],
      'ui_customization' => ['Checkout widget text, logo and layout', 'free', '/features/ui-customization', nil],
      'limit_cod' => ['Limit COD (hide/show COD by rules)', 'pro', '/features/limit-cod', 'Runs in test mode on Free'],
      'cod_fees' => ['COD fees', 'pro', '/features/cod-fees', 'Runs in test mode on Free'],
      'prepaid_discount' => ['Prepaid discount (discount for paying 100% online)', 'pro', '/features/prepaid-discount', nil],
      'address_autofill' => ['Address autofill (India)', 'pro', '/features/otp/pre-order', nil],
      'sms_templates' => ['Custom SMS templates (approval requests)', 'pro', '/features/notifications', nil],
      'abandoned_cart_export' => ['COD King abandoned carts: search, details, export', 'pro', '/usage-analytics/cod-king-abandoned-carts', nil],
      'branded_whatsapp' => ['Business Brand WhatsApp notifications from your own number', 'enterprise', '/features/whatsapp', nil],
      'onepass' => ['OnePass verification (verify once across stores)', 'enterprise', '/features/otp/pre-order', nil],
      'local_sms_gateway' => ['Local SMS gateway / branded sender ID', 'enterprise', '/networks', nil],
      'shopify_plus_checkout_otp' => ['OTP on the Shopify checkout page', 'enterprise_plus', '/features/shopify-plus-widget', 'Also requires a Shopify Plus store'],
      'remove_branding' => ['Remove COD King branding from the widget', 'enterprise_plus', '/features/ui-customization', nil]
    }.freeze

    module_function

    def tier_for(shop)
      return 'free' if shop.charge_id.blank?

      name = shop.plan&.name.to_s.downcase
      return 'enterprise_plus' if name.include?('enterprise plus') || name.include?('enterprise_plus') || name.include?('enterprise premium')
      return 'enterprise' if name.include?('enterprise') || name.include?('premium') || name.include?('india_budget')
      return 'pro' if name.include?('pro')

      'free'
    end

    def rank(tier)
      TIERS.index(tier) || 0
    end

    def plan_for(tier)
      PLANS.find { |plan| plan[:tier] == tier }
    end

    # Case-insensitive lookup by key or words in the label, e.g. "branding".
    def find_feature(query)
      text = query.to_s.downcase.strip
      return nil if text.empty?

      FEATURES.find { |key, (label, *)| key == text.tr(' ', '_') || label.downcase.include?(text) || text.include?(key.tr('_', ' ')) }
    end
  end
end
