# Raw Shopify Partner API app event for the COD King app (see
# Churn::PartnerAppEventsSync). Keyed on a synthetic external_key because
# Partner API events have no id.
class PartnerAppEvent < ApplicationRecord
  INSTALLED = 'RELATIONSHIP_INSTALLED'.freeze
  UNINSTALLED = 'RELATIONSHIP_UNINSTALLED'.freeze
  CHARGE_ACTIVATED = 'SUBSCRIPTION_CHARGE_ACTIVATED'.freeze
  CHARGE_CANCELED = 'SUBSCRIPTION_CHARGE_CANCELED'.freeze
  CHARGE_FROZEN = 'SUBSCRIPTION_CHARGE_FROZEN'.freeze
  CHARGE_UNFROZEN = 'SUBSCRIPTION_CHARGE_UNFROZEN'.freeze

  TRACKED_TYPES = [INSTALLED, UNINSTALLED, CHARGE_ACTIVATED, CHARGE_CANCELED, CHARGE_FROZEN, CHARGE_UNFROZEN].freeze

  scope :of_type, ->(type) { where(event_type: type) }
  scope :for_domain, ->(domain) { where(shopify_domain: domain) }
  scope :live_charges, -> { where(charge_test: false) }
  scope :between, ->(from, to) { where(occurred_at: from..to) }

  def paid_charge?
    charge_amount.to_f.positive?
  end
end
