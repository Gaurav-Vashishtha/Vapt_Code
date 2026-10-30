# One churn event per row, built by Churn::ChurnedStoresSyncJob.
#   uninstalled            — app uninstalled
#   subscription_cancelled — recurring charge cancelled while the app stayed installed
#   downgraded_to_free     — paid plan replaced by the $0 Free plan
class ChurnedStore < ApplicationRecord
  TYPES = {
    'uninstalled' => 'Uninstalled',
    'subscription_cancelled' => 'Subscription cancelled',
    'downgraded_to_free' => 'Downgraded to Free'
  }.freeze
  SUBSCRIPTION_TYPES = %w[subscription_cancelled downgraded_to_free].freeze

  belongs_to :uninstalled_shop, optional: true
  belongs_to :shop, optional: true

  validates :source_key, :churn_type, :shopify_domain, :churned_at, presence: true
  validates :churn_type, inclusion: { in: TYPES.keys }

  scope :in_period, ->(from, to) { where(churned_at: from..to) }
  scope :uninstalls, -> { where(churn_type: 'uninstalled') }
  scope :subscription_churn, -> { where(churn_type: SUBSCRIPTION_TYPES) }
  scope :recent_first, -> { order(churned_at: :desc) }

  def type_label
    TYPES[churn_type] || churn_type.to_s.humanize
  end

  def store_age_days
    return nil unless store_created_on
    (churned_at.to_date - store_created_on).to_i
  end
end
