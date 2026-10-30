require "administrate/base_dashboard"

# /admin/country_plan_offer_redemptions — which shops used which country offer (read-only).
class CountryPlanOfferRedemptionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    country_plan_offer: Field::BelongsTo,
    shop_id: Field::Number.with_options(searchable: true),
    charge_id: Field::String,
    status: Field::String,
    activated_at: Field::DateTime,
    created_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id country_plan_offer shop_id status activated_at created_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id country_plan_offer shop_id charge_id status activated_at created_at].freeze
  FORM_ATTRIBUTES = [].freeze
  COLLECTION_FILTERS = {}.freeze
end
