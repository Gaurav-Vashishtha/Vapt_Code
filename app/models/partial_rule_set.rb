class PartialRuleSet < ApplicationRecord
  belongs_to :shop

  default_scope { order(position: :asc, id: :asc) }

  before_create :set_position
  before_save :normalize_custom_save_text
  before_validation :normalize_cart_items_range
  before_validation :normalize_repeat_customer_fields
  validate :cart_items_range_bounds
  after_destroy_commit :schedule_sync_partial_rule_sets_metafield

  # Description template placeholders:
  # {{pay_now}} - Amount to pay now (with currency)
  # {{pay_later}} - Amount to pay on delivery (with currency)
  # {{total}} - Total amount (with currency)
  # {{discount}} - Discount amount (with currency)
  # {{cod_fee}} - COD fee amount (with currency)
  #
  # Default templates by amount_type:
  DEFAULT_TEMPLATES = {
    "cod" => "Pay {{total}} on delivery",
    "cod_with_fee" => "Pay {{total}} on delivery ({{cod_fee}} COD fee applicable)",
    "percentage_100" => "Pay {{pay_now}} now (prepaid)",
    "percentage_100_with_discount" => "Pay {{pay_now}} now and get {{discount}} off",
    "percentage" => "Pay {{pay_now}} now and {{pay_later}} on delivery",
    "fixed" => "Pay {{pay_now}} now and {{pay_later}} on delivery",
    "cod_fee_exception" => "Pay {{pay_now}} cod fee now, remaining {{pay_later}} on delivery"
  }.freeze

  def default_template
    if amount_type == "cod"
      cod_fee_amount = amount_to_show.present? ? amount_to_show.to_f : amount.to_f
      cod_fee_amount > 0 ? DEFAULT_TEMPLATES["cod_with_fee"] : DEFAULT_TEMPLATES["cod"]
    elsif amount_type == "percentage" && amount.to_f == 100
      DEFAULT_TEMPLATES["percentage_100"]
    elsif amount_type == "percentage"
      DEFAULT_TEMPLATES["percentage"]
    elsif amount_type == "fixed" && amount.to_f == 0 && amount_to_show.present?
      DEFAULT_TEMPLATES["cod_fee_exception"]
    else
      DEFAULT_TEMPLATES["fixed"]
    end
  end

  def effective_template
    description_template.present? ? description_template : default_template
  end

  # Zipcode blacklist helpers
  # zipcode_blacklist: comma-separated list of zipcodes or ranges (e.g., "110001,110002,400001-400010")
  
  def zipcode_blacklist_array
    return [] if zipcode_blacklist.blank?
    zipcode_blacklist.split(",").map(&:strip).reject(&:blank?)
  end

  def zipcode_blacklisted?(zipcode)
    return false if !zipcode_blacklist_enabled || zipcode.blank?

    normalized_zipcode = zipcode.to_s.strip.gsub(/\s+/, "")
    return false if normalized_zipcode.blank?

    zipcode_blacklist_array.any? do |entry|
      if entry.include?("-")
        # Range: e.g., "400001-400010"
        range_start, range_end = entry.split("-").map(&:strip)
        normalized_zipcode >= range_start && normalized_zipcode <= range_end
      else
        # Exact match
        normalized_zipcode == entry
      end
    end
  end

  def zipcode_whitelist_array
    return [] if zipcode_whitelist.blank?
    zipcode_whitelist.split(",").map(&:strip).reject(&:blank?)
  end

  def zipcode_whitelisted?(zipcode)
    return true unless zipcode_whitelist_enabled
    return false if zipcode.blank?

    normalized_zipcode = zipcode.to_s.strip.gsub(/\s+/, "")
    return false if normalized_zipcode.blank?

    entries = zipcode_whitelist_array
    return true if entries.empty?

    entries.any? do |entry|
      if entry.include?("-")
        range_start, range_end = entry.split("-").map(&:strip)
        normalized_zipcode >= range_start && normalized_zipcode <= range_end
      else
        normalized_zipcode == entry
      end
    end
  end

  # RTO engine gate
  # rto_engine is NULL until a merchant opts this rule in, so an unconfigured
  # rule can never be hidden by risk scoring.
  #
  #   { "enabled" => true, "hide_at_band" => "high", "min_score" => 60 }
  #
  # hide_at_band and min_score are OR'd: whichever trips first hides the rule.
  RTO_BAND_RANK = { "low" => 0, "medium" => 1, "high" => 2 }.freeze
  RTO_DEFAULT_BAND = "high"

  def rto_engine_config
    rto_engine.is_a?(Hash) ? rto_engine : {}
  end

  def rto_engine_enabled?
    ActiveModel::Type::Boolean.new.cast(rto_engine_config["enabled"]).present?
  end

  def rto_hide_at_band
    band = rto_engine_config["hide_at_band"].to_s.downcase
    RTO_BAND_RANK.key?(band) ? band : RTO_DEFAULT_BAND
  end

  # nil means "no numeric cutoff configured" — band alone decides.
  def rto_min_score
    raw = rto_engine_config["min_score"]
    return nil if raw.nil? || raw.to_s.strip.empty?

    raw.to_i.clamp(0, 100)
  end

  # Decides whether a scored decision should hide this rule.
  # Callers pass the /rto/decision response fields straight through.
  def rto_engine_hides?(band:, score: nil)
    return false unless rto_engine_enabled?

    band_rank = RTO_BAND_RANK[band.to_s.downcase]
    return true if band_rank && band_rank >= RTO_BAND_RANK[rto_hide_at_band]

    cutoff = rto_min_score
    return false if cutoff.nil? || score.nil?

    score.to_i >= cutoff
  end

  # Cart item count gate
  # cart_items_range is NULL until a merchant sets a bound, so an unconfigured
  # rule never makes the storefront wait on cart.js for the item count.
  #
  #   { "min_cart_items" => 2, "max_cart_items" => 5 }
  #
  # Either bound may be nil (open-ended). Counts are total quantity in the cart.
  def min_cart_items
    cart_items_range_value("min_cart_items")
  end

  def max_cart_items
    cart_items_range_value("max_cart_items")
  end

  def cart_items_range?
    !min_cart_items.nil? || !max_cart_items.nil?
  end

  def cart_items_count_allowed?(count)
    return true unless cart_items_range?

    count = count.to_i
    return false if min_cart_items && count < min_cart_items
    return false if max_cart_items && count > max_cart_items

    true
  end

  # variant_scope: 'all' | 'include' | 'exclude'
  # - all: rule applies regardless of variant
  # - include: rule applies only when ALL cart variants are in variant_ids
  #            (or ANY when match_any_product is true)
  # - exclude: rule applies when NONE of the cart variants are in variant_ids
  #
  # Works alongside product_scope (AND logic):
  # - Both product AND variant conditions must be satisfied for rule to apply
  #
  # match_any_product (rule-wide boolean, default false):
  # - When true, the "include" branch of product/variant/collection scopes passes
  #   as long as ANY cart item satisfies the condition (OR semantics) instead of
  #   requiring every cart item to satisfy it (AND semantics).

  def variant_ids_array
    return [] if variant_ids.blank?
    Array(variant_ids).map(&:to_s).reject(&:blank?)
  end

  def variant_matches?(cart_variant_ids)
    return true if variant_scope.blank? || variant_scope == "all"
    return true if variant_ids_array.empty?

    cart_ids = Array(cart_variant_ids).map(&:to_s).reject(&:blank?)
    return variant_scope == "exclude" if cart_ids.empty?

    case variant_scope
    when "include"
      if match_any_product
        cart_ids.any? { |vid| variant_ids_array.include?(vid) }
      else
        cart_ids.all? { |vid| variant_ids_array.include?(vid) }
      end
    when "exclude"
      cart_ids.none? { |vid| variant_ids_array.include?(vid) }
    else
      true
    end
  end

  def collection_ids_array
    return [] if collection_ids.blank?
    Array(collection_ids).map(&:to_s).reject(&:blank?)
  end

  def collection_matches?(cart_product_collections_map)
    return true if collection_scope.blank? || collection_scope == "all"
    return true if collection_ids_array.empty?

    rule_set = collection_ids_array.to_set
    products = cart_product_collections_map.is_a?(Hash) ? cart_product_collections_map.values : Array(cart_product_collections_map)
    return collection_scope == "exclude" if products.empty?

    matcher = ->(colls) { Array(colls).map(&:to_s).any? { |c| rule_set.include?(c) } }

    case collection_scope
    when "include"
      match_any_product ? products.any?(&matcher) : products.all?(&matcher)
    when "exclude"
      products.none?(&matcher)
    else
      true
    end
  end

  # product_scope: 'all' | 'include' | 'exclude'
  # - all: rule applies regardless of product
  # - include: rule applies only when product/cart is in product_ids
  # - exclude: rule applies when product/cart is not in product_ids
  # Rules that need to know whether the shopper has ordered before: prepaid
  # (100%) rules with the repeat-customer discount, COD rules with a cooling
  # period.
  def self.existing_customer_check_needed?(shop)
    where(shop: shop, is_enabled: true).where(
      "(amount_type = 'percentage' AND amount = 100 AND (repeat_customer_discount ->> 'enabled') = 'true') " \
      "OR (amount_type = 'cod' AND (cod_cooling_period ->> 'enabled') = 'true')"
    ).exists?
  end

  def self.find_rule_sets_by_product_and_shop(shop, product_id)
    scope = PartialRuleSet.where(shop: shop, is_enabled: true)
    return scope if product_id.blank?

    product_id_str = product_id.to_s
    scope.where(
      "(
        (COALESCE(product_scope, 'all') = 'all')
        OR (product_scope = 'include' AND product_ids @> ARRAY[:product_id]::varchar[])
        OR (product_scope = 'exclude' AND (product_ids IS NULL OR NOT (product_ids @> ARRAY[:product_id]::varchar[])))
      )",
      product_id: product_id_str
    )
  end

  private

  # Keep the two JSON settings to known keys with real types; NULL stays NULL.
  def normalize_repeat_customer_fields
    if repeat_customer_discount.is_a?(Hash)
      raw = repeat_customer_discount.stringify_keys
      self.repeat_customer_discount = {
        "enabled" => ActiveModel::Type::Boolean.new.cast(raw["enabled"]) == true,
        "discount_type" => raw["discount_type"].to_s == "percentage" ? "percentage" : "fixed",
        "discount_value" => [raw["discount_value"].to_f, 0].max
      }
    end

    if cod_cooling_period.is_a?(Hash)
      raw = cod_cooling_period.stringify_keys
      days = Integer(raw["days"].to_s.strip, exception: false)
      self.cod_cooling_period = {
        "enabled" => ActiveModel::Type::Boolean.new.cast(raw["enabled"]) == true,
        "days" => days && days.positive? ? days : nil
      }.compact
    end
  end

  def normalize_custom_save_text
    self.custom_save_text = custom_save_text.to_s.strip.presence
    self.shipping_charge_text = shipping_charge_text.to_s.strip.presence
  end

  def cart_items_range_value(key)
    return nil unless cart_items_range.is_a?(Hash)

    raw = cart_items_range[key]
    return nil if raw.nil? || raw.to_s.strip.empty?

    Integer(raw.to_s.strip, exception: false)
  end

  # Keep only the two known keys as integers; no bound at all stores NULL.
  def normalize_cart_items_range
    return if cart_items_range.nil?
    return self.cart_items_range = nil unless cart_items_range.is_a?(Hash)

    range = {
      "min_cart_items" => min_cart_items,
      "max_cart_items" => max_cart_items
    }.compact
    self.cart_items_range = range.presence
  end

  def cart_items_range_bounds
    return unless cart_items_range?

    if [min_cart_items, max_cart_items].compact.any?(&:negative?)
      errors.add(:cart_items_range, "cart item counts can't be negative")
    elsif min_cart_items && max_cart_items && max_cart_items < min_cart_items
      errors.add(:cart_items_range, "max cart items must be greater than or equal to min cart items")
    end
  end

  def schedule_sync_partial_rule_sets_metafield
    return unless shop_id.present?
    ShopifyJobs::RefreshPartialRuleSetsMetafieldJob.perform_later(shop_id)
  end

  def set_position
    return if position.present? && position != 0
    max_pos = PartialRuleSet.unscoped.where(shop_id: shop_id).maximum(:position) || -1
    self.position = max_pos + 1
  end
end
