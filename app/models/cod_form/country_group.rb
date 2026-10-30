# frozen_string_literal: true

module CodForm
  # cod_form_country_groups (ARCHITECTURE.md B.13, CAP-4). First matching group (by position) wins.
  class CountryGroup < ApplicationRecord
    include CodForm::AdminAudited

    self.table_name = "cod_form_country_groups"

    before_validation :normalize_country_codes

    validates :name, presence: true, length: { maximum: 255 }
    validates :position, numericality: { only_integer: true }
    validates :active, inclusion: { in: [true, false] }
    validate :country_codes_shape

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(position: :asc, id: :asc) }
    # Active groups that contain the ISO2 country code, in position order.
    scope :for_country, lambda { |country_code|
      code = country_code.to_s.strip.upcase
      code.empty? ? none : active.ordered.where("cod_form_country_groups.country_codes @> ?", [code].to_json)
    }

    def include_country?(country_code)
      Array(country_codes).include?(country_code.to_s.strip.upcase)
    end

    private

    def normalize_country_codes
      return unless country_codes.is_a?(Array)

      self.country_codes = country_codes.map { |code| code.to_s.strip.upcase }.reject(&:empty?).uniq
    end

    def country_codes_shape
      return if country_codes.is_a?(Array) && country_codes.all? { |code| code.is_a?(String) && code.match?(/\A[A-Z]{2}\z/) }

      errors.add(:country_codes, "must be a JSON array of ISO 3166-1 alpha-2 codes, e.g. [\"HU\", \"CO\"]")
    end
  end
end
