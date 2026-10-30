# frozen_string_literal: true

require "ipaddr"

module CodForm
  # cod_block_entries (ARCHITECTURE.md B.7, C.5, FRD-1).
  class BlockEntry < ApplicationRecord
    self.table_name = "cod_block_entries"
    self.filter_attributes = filter_attributes + %i[value value_normalized]

    KIND_PHONE = "phone"
    KIND_EMAIL = "email"
    KIND_IP = "ip"
    KINDS = [KIND_PHONE, KIND_EMAIL, KIND_IP].freeze
    MAX_PER_KIND = 5_000

    belongs_to :shop

    before_validation :set_value_normalized

    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :value, presence: true, length: { maximum: 255 }
    validates :value_normalized, presence: true,
                                 uniqueness: { scope: %i[shop_id kind], message: "is already on the list" }
    validates :note, length: { maximum: 255 }, allow_nil: true
    validate :value_format
    validate :per_kind_limit, on: :create

    scope :of_kind, ->(kind) { where(kind: kind.to_s) }

    # phone: digits only, no leading zeros; email: lower-case trimmed; ip: as is, or CIDR a.b.c.d/nn.
    def self.normalize(kind, value)
      text = value.to_s.strip
      case kind.to_s
      when KIND_PHONE then text.gsub(/\D/, "").sub(/\A0+/, "")
      when KIND_EMAIL then text.downcase
      else text
      end
    end

    private

    def set_value_normalized
      self.value = value.to_s.strip if value
      self.value_normalized = self.class.normalize(kind, value)
    end

    def value_format
      return if value_normalized.blank?

      case kind
      when KIND_PHONE
        errors.add(:value, "must contain 5 to 15 digits") unless value_normalized.match?(/\A\d{5,15}\z/)
      when KIND_EMAIL
        errors.add(:value, "must be an email address or *@domain") unless value_normalized.match?(/\A(\*|[^@\s*]+)@[^@\s*]+\.[^@\s*]+\z/)
      when KIND_IP
        errors.add(:value, "must be an IP address or CIDR range") unless valid_ip?(value_normalized)
      end
    end

    def valid_ip?(text)
      IPAddr.new(text)
      true
    rescue IPAddr::Error, ArgumentError
      false
    end

    def per_kind_limit
      return unless shop_id && kind.present?
      return if self.class.where(shop_id: shop_id, kind: kind).count < MAX_PER_KIND

      errors.add(:base, "limit reached: at most #{MAX_PER_KIND} #{kind} entries")
    end
  end
end
