# frozen_string_literal: true

module CodForm
  # cod_form_integrations (ARCHITECTURE.md B.18). credentials are never serialised or logged.
  # Not to be confused with the existing top-level ::Integration model.
  class Integration < ApplicationRecord
    self.table_name = "cod_form_integrations"
    self.filter_attributes = filter_attributes + %i[credentials]

    PROVIDERS = %w[google_sheets klaviyo omnisend rabbitpay].freeze
    STATUS_DISCONNECTED = "disconnected"
    STATUS_CONNECTED = "connected"
    STATUS_ERROR = "error"
    STATUSES = [STATUS_DISCONNECTED, STATUS_CONNECTED, STATUS_ERROR].freeze
    LAST_ERROR_MAX = 255

    belongs_to :shop

    validates :provider, presence: true, inclusion: { in: PROVIDERS },
                         uniqueness: { scope: :shop_id }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validate :json_shapes

    scope :connected, -> { where(status: STATUS_CONNECTED) }
    scope :for_provider, ->(provider) { where(provider: provider.to_s) }

    # The shop's row for a provider; created (disconnected) on first use.
    def self.for(shop, provider)
      shop_id = shop.respond_to?(:id) ? shop.id : shop
      find_or_create_by!(shop_id: shop_id, provider: provider.to_s)
    rescue ActiveRecord::RecordNotUnique
      find_by!(shop_id: shop_id, provider: provider.to_s)
    end

    def connected?
      status == STATUS_CONNECTED
    end

    def mark_success!
      update!(status: STATUS_CONNECTED, last_error: nil, last_success_at: Time.current)
    end

    # `message` must not contain PII or secrets; it is shown to the merchant.
    def mark_error!(message)
      update!(status: STATUS_ERROR, last_error: message.to_s.truncate(LAST_ERROR_MAX))
    end

    def disconnect!
      update!(status: STATUS_DISCONNECTED, credentials: {}, last_error: nil)
    end

    # Credentials never leave through as_json / to_json.
    def serializable_hash(options = nil)
      options = (options || {}).dup
      options[:except] = Array(options[:except]).map(&:to_s) | %w[credentials]
      super(options)
    end

    private

    def json_shapes
      %i[credentials config].each do |column|
        errors.add(column, "must be a JSON object") unless self[column].is_a?(Hash)
      end
    end
  end
end
