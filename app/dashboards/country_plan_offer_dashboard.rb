require "administrate/base_dashboard"

# /admin/country_plan_offers — run a plan offer for one country (price and/or free trial).
# PlansController#upgrade applies the running offer for the shop's country to the Shopify charge.
class CountryPlanOfferDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String.with_options(help: "Internal label, e.g. EG founding merchants."),
    country_code: Field::String.with_options(help: "2-letter country code of the shop, e.g. EG, PK."),
    plan_name: Field::Select.with_options(
      collection: -> { Plan.where("price > 0").order(:price).pluck(:name) },
      help: "The paid plan this offer applies to."
    ),
    price_usd: Field::Number.with_options(
      decimals: 2,
      help: "Monthly price charged instead of the plan price (min 0.01). Shopify keeps this price until the merchant approves a new charge. Leave empty to keep the plan price."
    ),
    trial_days: Field::Number.with_options(
      help: "Free days before billing starts; Shopify then bills the price automatically. 90 = about 3 months. Leave empty for no trial."
    ),
    max_redemptions: Field::Number.with_options(help: "How many stores can use it (approved charges). Empty = unlimited."),
    redemptions_count: Field::Number,
    starts_at: Field::DateTime.with_options(help: "Empty = from now."),
    ends_at: Field::DateTime.with_options(help: "Empty = no end date."),
    active: Field::Boolean.with_options(help: "Untick to stop the offer immediately (already approved charges keep their terms)."),
    badge: Field::String.with_options(help: "Short text on the plan card, in the merchant's language. Empty = 'N days free'."),
    note: Field::Text,
    redemptions: Field::HasMany.with_options(class_name: "CountryPlanOfferRedemption"),
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id name country_code plan_name price_usd trial_days redemptions_count max_redemptions active ends_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id name country_code plan_name price_usd trial_days max_redemptions redemptions_count
                            starts_at ends_at active badge note redemptions created_at updated_at].freeze
  FORM_ATTRIBUTES = %i[name country_code plan_name price_usd trial_days max_redemptions starts_at ends_at active badge note].freeze
  COLLECTION_FILTERS = {}.freeze

  def display_resource(offer)
    "#{offer.name} (#{offer.country_code} · #{offer.plan_name})"
  end
end
