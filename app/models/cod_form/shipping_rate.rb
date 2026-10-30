# frozen_string_literal: true

module CodForm
  # cod_shipping_rates (ARCHITECTURE.md B.4, C.3). price_cents is integer cents in `currency`.
  class ShippingRate < ApplicationRecord
    self.table_name = "cod_shipping_rates"

    SOURCE_MANUAL = "manual"
    SOURCE_CSV = "csv"
    SOURCES = [SOURCE_MANUAL, SOURCE_CSV].freeze

    belongs_to :shop

    before_validation :normalize_currency

    validates :name, presence: true, length: { maximum: 255 }
    validates :description, length: { maximum: 255 }, allow_nil: true
    validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency, format: { with: /\A[A-Z]{3}\z/ }, allow_nil: true
    validates :position, numericality: { only_integer: true }
    validates :source, presence: true, inclusion: { in: SOURCES }
    validates :active, inclusion: { in: [true, false] }
    validate :conditions_shape

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(position: :asc, id: :asc) }

    def free?
      price_cents.to_i.zero?
    end

    # Engine / admin API representation (C.3), string keys.
    def to_engine_hash
      {
        "id" => id, "name" => name, "description" => description,
        "price_cents" => price_cents, "currency" => currency, "position" => position,
        "active" => active, "source" => source, "conditions" => conditions
      }
    end

    private

    def normalize_currency
      self.currency = currency.to_s.strip.upcase.presence
    end

    def conditions_shape
      errors.add(:conditions, "must be a JSON object") unless conditions.is_a?(Hash)
    end
  end
end
