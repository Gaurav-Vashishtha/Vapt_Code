require "administrate/base_dashboard"

# /admin/shop_charge_overrides — support team sets what a shop pays per WhatsApp message.
# PricingJobs::DynamicChargeJob multiplies the normal price of each WhatsApp message (legacy
# and BSP, plan tier or India V3 rate) by the multiplier of its category, except BSP messages
# when a BSP commission is set: those are charged that flat USD amount instead.
class ShopChargeOverrideDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    # A plain number box on purpose: a Shop select would load every shop in production.
    shop_id: Field::Number.with_options(
      searchable: true,
      help: "The shop's ID (Shops → id). One override per shop."
    ),
    shop_domain: Field::String.with_options(searchable: false),
    whatsapp_utility_multiplier: Field::Number.with_options(
      decimals: 4,
      help: "Order confirmation, fulfilment, OTP and COD verification messages. 1 = normal price, 0.5 = half, 0 = free. Leave empty for no override."
    ),
    whatsapp_marketing_multiplier: Field::Number.with_options(
      decimals: 4,
      help: "Abandoned cart, COD → prepaid and first-purchase messages. 1 = normal price, 0.5 = half, 0 = free. Leave empty for no override."
    ),
    whatsapp_bsp_commission_usd: Field::Number.with_options(
      decimals: 6,
      help: "Flat charge in USD per BSP WhatsApp message (own-number messages), not a multiplier: 0.001 = $0.001 per message, 0 = free. When set, the multipliers above no longer apply to BSP messages. Leave empty to use the normal BSP price."
    ),
    note: Field::String.with_options(help: "Why the override was given (deal, ticket number, who approved)."),
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    shop_id
    shop_domain
    whatsapp_utility_multiplier
    whatsapp_marketing_multiplier
    whatsapp_bsp_commission_usd
    updated_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    shop_id
    shop_domain
    whatsapp_utility_multiplier
    whatsapp_marketing_multiplier
    whatsapp_bsp_commission_usd
    note
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    shop_id
    whatsapp_utility_multiplier
    whatsapp_marketing_multiplier
    whatsapp_bsp_commission_usd
    note
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(override)
    "Charge override ##{override.id} (shop #{override.shop_id})"
  end
end
