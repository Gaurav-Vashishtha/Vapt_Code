# frozen_string_literal: true

module CodForm
  # tracking_pixels (ARCHITECTURE.md B.10, C.6). access_token is never serialised or logged.
  class TrackingPixel < ApplicationRecord
    self.table_name = "tracking_pixels"
    self.filter_attributes = filter_attributes + %i[access_token]

    PLATFORMS = %w[meta tiktok ga4 google_ads snapchat pinterest].freeze
    MAX_PER_PLATFORM = 5
    TOKEN_MASK = "••••"

    belongs_to :shop

    before_validation :strip_identifiers

    validates :platform, presence: true, inclusion: { in: PLATFORMS }
    validates :pixel_id, presence: true, length: { maximum: 255 },
                         uniqueness: { scope: %i[shop_id platform], message: "is already added for this platform" }
    validates :position, numericality: { only_integer: true }
    validates :enabled, inclusion: { in: [true, false] }
    validate :json_shapes
    validate :per_platform_limit, on: :create

    scope :enabled, -> { where(enabled: true) }
    scope :for_platform, ->(platform) { where(platform: platform.to_s) }
    scope :ordered, -> { order(position: :asc, id: :asc) }

    # "••••1234", or nil when there is no token (C.6 `access_token_masked`).
    def access_token_masked
      return nil if access_token.blank?

      "#{TOKEN_MASK}#{access_token.to_s.last(4)}"
    end

    # The token never leaves through as_json / to_json.
    def serializable_hash(options = nil)
      options = (options || {}).dup
      options[:except] = Array(options[:except]).map(&:to_s) | %w[access_token]
      super(options)
    end

    private

    def strip_identifiers
      self.pixel_id = pixel_id.to_s.strip if pixel_id
      self.access_token = access_token.to_s.strip.presence if access_token
    end

    def json_shapes
      %i[config targeting].each do |column|
        errors.add(column, "must be a JSON object") unless self[column].is_a?(Hash)
      end
    end

    def per_platform_limit
      return unless shop_id && platform.present?
      return if self.class.where(shop_id: shop_id, platform: platform).count < MAX_PER_PLATFORM

      errors.add(:base, "limit reached: at most #{MAX_PER_PLATFORM} #{platform} pixels per shop")
    end
  end
end
