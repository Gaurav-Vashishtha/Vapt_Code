class FollowUp < ApplicationRecord
  STATUSES = {
    pending: "pending",
    resolved: "resolved"
  }.freeze

  # Either a live shop or (for stores that uninstalled) the uninstall snapshot.
  belongs_to :shop, optional: true
  belongs_to :uninstalled_shop, optional: true
  has_many :follow_up_comments, dependent: :destroy

  enum status: STATUSES

  validates :notes, :source_tab, presence: true
  validate :owner_present
  validates :resolved_notes, :resolved_source_tab, presence: true, if: :resolved?

  before_validation :set_resolved_at_timestamp

  scope :recent_first, -> { order(created_at: :desc) }
  scope :pending_first, -> { order(Arel.sql("CASE WHEN status = 'pending' THEN 0 ELSE 1 END"), created_at: :desc) }

  def owner
    shop || uninstalled_shop
  end

  def owner_domain
    shop&.shopify_domain || uninstalled_shop&.shop_domain
  end

  def owner_display_name
    shop&.shop_owner.presence || uninstalled_shop&.owner_name.presence
  end

  private

  def owner_present
    errors.add(:base, 'Follow-up must belong to a shop or an uninstalled shop') if shop_id.blank? && uninstalled_shop_id.blank?
  end

  def set_resolved_at_timestamp
    return unless resolved? && resolved_at.blank?
    self.resolved_at = Time.current
  end
end
