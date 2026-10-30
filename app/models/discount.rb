class Discount < ApplicationRecord
  belongs_to :shop

  METHODS        = %w[code automatic].freeze
  DISCOUNT_TYPES = %w[amount_off percentage buy_x_get_y].freeze
  APPLIES_TO     = %w[all products collections].freeze
  MIN_REQ_TYPES  = %w[subtotal quantity].freeze

  enum :sync_status, { pending: "pending", synced: "synced", failed: "failed" }, default: "pending"

  validates :title, presence: true
  validates :method, inclusion: { in: METHODS }
  validates :discount_type, inclusion: { in: DISCOUNT_TYPES }
  validates :applies_to, inclusion: { in: APPLIES_TO }
  validates :minimum_requirement_type, inclusion: { in: MIN_REQ_TYPES }, allow_nil: true

  validates :code, presence: true, if: :code_method?
  validates :code, uniqueness: { scope: :shop_id, case_sensitive: false }, allow_blank: true
  validate  :code_absent_for_automatic
  validate  :bxgy_config_present_for_bxgy
  validates :value, presence: true, unless: :buy_x_get_y?

  scope :active,         -> { where(is_active: true) }
  scope :widget_visible, -> { active.where(widget_enabled: true, sync_status: "synced") }

  # Pushes this discount to Shopify (create or update) and records the result.
  # Synchronous — safe to call inline from a controller. Returns the Upsert result hash.
  def sync_to_shopify!
    result = ShopifyServices::Discounts::Upsert.call(self)
    if result[:ok]
      update!(sync_status: "synced", shopify_gid: result[:gid], sync_error: nil)
      refresh_widget_payload!
    else
      update!(sync_status: "failed", sync_error: result[:error])
    end
    result
  end

  def code_method?
    method == "code"
  end

  def automatic_method?
    method == "automatic"
  end

  def buy_x_get_y?
    discount_type == "buy_x_get_y"
  end

  def product_gids_array
    Array(product_gids).map(&:to_s).reject(&:blank?)
  end

  def collection_gids_array
    Array(collection_gids).map(&:to_s).reject(&:blank?)
  end

  def excluded_product_gids_array
    Array(excluded_product_gids).map(&:to_s).reject(&:blank?)
  end

  private

  # Best-effort: rebuild the codk.lightweight_settings metafield so the widget's
  # preload cache reflects the new/updated coupon. The /script endpoint reads fresh
  # from the DB anyway, so failures here are non-fatal.
  def refresh_widget_payload!
    shop&.setting&.sync_lightweight_metafields_and_touch_refreshed_at
  rescue => e
    Rails.logger.warn("[Discount#sync_to_shopify!] metafield refresh failed shop=#{shop&.shopify_domain} error=#{e.message}")
  end

  def code_absent_for_automatic
    errors.add(:code, "must be blank for automatic discounts") if automatic_method? && code.present?
  end

  def bxgy_config_present_for_bxgy
    return unless buy_x_get_y?

    errors.add(:bxgy_config, "is required for buy X get Y discounts") if bxgy_config.blank?
  end
end
