# frozen_string_literal: true

module CodForm
  # cod_form_sessions (ARCHITECTURE.md B.8). One row per opened form.
  # Holds buyer PII: never log a row (inspect is filtered) or its contact / address / ip.
  class Session < ApplicationRecord
    self.table_name = "cod_form_sessions"
    self.filter_attributes = filter_attributes +
                             %i[contact address ip user_agent phone_normalized email_normalized
                                custom_fields recovery_token idempotency_key]

    STATUS_OPEN = "open"
    STATUS_OTP_PENDING = "otp_pending"
    STATUS_ORDERING = "ordering"
    STATUS_ORDERED = "ordered"
    STATUS_HANDOFF_PARTIAL = "handoff_partial"
    STATUS_HANDOFF_PREPAID = "handoff_prepaid"
    STATUS_BLOCKED = "blocked"
    STATUS_ABANDONED = "abandoned"
    STATUS_RECOVERED = "recovered"
    STATUS_EXPIRED = "expired"
    STATUSES = [
      STATUS_OPEN, STATUS_OTP_PENDING, STATUS_ORDERING, STATUS_ORDERED, STATUS_HANDOFF_PARTIAL,
      STATUS_HANDOFF_PREPAID, STATUS_BLOCKED, STATUS_ABANDONED, STATUS_RECOVERED, STATUS_EXPIRED
    ].freeze
    # Statuses from which an order may be started (F.2 step 1, compare-and-set).
    ORDERABLE_STATUSES = [STATUS_OPEN, STATUS_OTP_PENDING, STATUS_BLOCKED, STATUS_ABANDONED, STATUS_RECOVERED].freeze
    HANDOFF_STATUSES = [STATUS_HANDOFF_PARTIAL, STATUS_HANDOFF_PREPAID].freeze

    SOURCES = %w[product cart drawer quick_buy api embedded recovery].freeze
    DEVICES = %w[mobile tablet desktop].freeze
    TOKEN_TTL = 2.hours
    RECOVERY_TOKEN_LENGTH = 24

    belongs_to :shop
    belongs_to :form, class_name: "CodForm::Form", foreign_key: :cod_form_id, optional: true

    before_validation :assign_defaults, on: :create

    validates :public_id, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :source, presence: true, inclusion: { in: SOURCES }
    validates :device, inclusion: { in: DEVICES }, allow_nil: true
    validates :expires_at, presence: true
    validates :order_total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :closes_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :live, -> { where(is_test: false) }
    scope :test_sessions, -> { where(is_test: true) }
    scope :with_order, -> { where.not(order_id: nil) }
    scope :with_status, ->(*statuses) { where(status: statuses.flatten.map(&:to_s)) }
    scope :created_between, ->(from, to) { where(created_at: from..to) }

    def expired?(now = Time.current)
      expires_at.present? && expires_at <= now
    end

    def ordered?
      order_id.present?
    end

    def test?
      is_test ? true : false
    end

    def otp_verified?
      otp_verified_at.present?
    end

    # F.2 step 13. `order` is the created Shopify order: an object responding to #id / #name
    # (ShopifyAPI::Order) or a Hash with "id" / "name" (and optionally "total_cents").
    # `attrs` may carry further columns to persist in the same write (order_total_cents, contact,
    # address, phone_normalized, email_normalized, ip, ...).
    def mark_ordered!(order, attrs = {})
      extra = attrs.to_h.stringify_keys
      total = extra.delete("order_total_cents") || order_value(order, "total_cents") ||
              (quote_snapshot.is_a?(Hash) ? quote_snapshot["total_cents"] : nil)

      update!(
        extra.merge(
          "status" => STATUS_ORDERED,
          "order_id" => order_value(order, "id").to_s,
          "order_name" => order_value(order, "name"),
          "order_total_cents" => total,
          "ordered_at" => Time.current,
          "order_error" => nil
        )
      )
      self
    end

    # Sets abandoned status and a recovery token (ABN-1). Returns the token.
    def mark_abandoned!(abandoned_cart_id: nil)
      token = recovery_token.presence || SecureRandom.urlsafe_base64(18)[0, RECOVERY_TOKEN_LENGTH]
      update!(status: STATUS_ABANDONED, abandoned_at: Time.current, recovery_token: token,
              abandoned_cart_id: abandoned_cart_id || self.abandoned_cart_id)
      token
    end

    private

    def assign_defaults
      self.public_id = SecureRandom.uuid if public_id.blank?
      self.expires_at ||= Time.current + TOKEN_TTL
    end

    def order_value(order, key)
      if order.is_a?(Hash)
        order[key] || order[key.to_sym]
      elsif order.respond_to?(key)
        order.public_send(key)
      end
    end
  end
end
