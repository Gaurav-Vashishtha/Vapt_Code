# frozen_string_literal: true

module CodForm
  # cod_offers (ARCHITECTURE.md B.5, C.4).
  class Offer < ApplicationRecord
    self.table_name = "cod_offers"

    OFFER_TYPES = %w[quantity bump upsell downsell threshold pre_upsell bundle].freeze
    STATUS_DRAFT = "draft"
    STATUS_ACTIVE = "active"
    STATUS_PAUSED = "paused"
    STATUS_ARCHIVED = "archived"
    STATUSES = [STATUS_DRAFT, STATUS_ACTIVE, STATUS_PAUSED, STATUS_ARCHIVED].freeze

    # Active offers allowed per shop, by offer_type (checked on activation).
    ACTIVE_LIMITS = { "quantity" => 50, "bump" => 20, "downsell" => 1 }.freeze
    MAX_BUMPS_SHOWN = 3

    belongs_to :shop
    belongs_to :ab_test, class_name: "CodForm::AbTest", optional: true

    validates :offer_type, presence: true, inclusion: { in: OFFER_TYPES }
    validates :name, presence: true, length: { maximum: 255 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :priority, numericality: { only_integer: true }
    validate :json_shapes
    validate :schedule_order
    validate :active_limit, if: :activating?
    validate :quantity_offer_overlap, if: :check_overlap?

    scope :active, -> { where(status: STATUS_ACTIVE) }
    scope :of_type, ->(type) { where(offer_type: type.to_s) }
    scope :ordered, -> { order(priority: :asc, id: :asc) }
    # Active and inside the optional schedule window.
    scope :active_now, lambda {
      now = Time.current
      active
        .where("cod_offers.starts_at IS NULL OR cod_offers.starts_at <= ?", now)
        .where("cod_offers.ends_at IS NULL OR cod_offers.ends_at > ?", now)
    }

    def active?
      status == STATUS_ACTIVE
    end

    def active_now?(now = Time.current)
      active? && (starts_at.nil? || starts_at <= now) && (ends_at.nil? || ends_at > now)
    end

    # Engine / admin API representation (C.4 common wrapper), string keys.
    def to_engine_hash
      {
        "id" => id, "offer_type" => offer_type, "name" => name, "status" => status,
        "priority" => priority, "targeting" => targeting, "config" => config,
        "ab_test_id" => ab_test_id,
        "starts_at" => starts_at&.utc&.iso8601, "ends_at" => ends_at&.utc&.iso8601
      }
    end

    private

    def activating?
      active? && (new_record? || status_changed? || offer_type_changed?)
    end

    def check_overlap?
      offer_type == "quantity" && active? && (new_record? || status_changed? || targeting_changed?)
    end

    def json_shapes
      %i[targeting config].each do |column|
        errors.add(column, "must be a JSON object") unless self[column].is_a?(Hash)
      end
    end

    def schedule_order
      return unless starts_at && ends_at && ends_at <= starts_at

      errors.add(:ends_at, "must be after starts_at")
    end

    def active_limit
      limit = ACTIVE_LIMITS[offer_type]
      return unless limit && shop_id

      others = self.class.where(shop_id: shop_id, offer_type: offer_type, status: STATUS_ACTIVE)
      others = others.where.not(id: id) if persisted?
      return if others.count < limit

      errors.add(:status, "limit reached: at most #{limit} active #{offer_type} offers per shop")
    end

    # OFF-2: a product may be in at most one active quantity offer (product_ids only; overlap
    # through collections is a warning of the admin API, not a validation).
    def quantity_offer_overlap
      return unless shop_id && targeting.is_a?(Hash)

      others = self.class.where(shop_id: shop_id, offer_type: "quantity", status: STATUS_ACTIVE)
      others = others.where.not(id: id) if persisted?
      offers = others.map(&:to_engine_hash) + [to_engine_hash]
      conflicts = CodForm::Engine::OfferOverlap.conflicts(offers)
      return if conflicts.blank?

      errors.add(:targeting, "a product can be in only one active quantity offer")
    end
  end
end
