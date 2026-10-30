# frozen_string_literal: true

class WhatsappInboxLabel < ApplicationRecord
  belongs_to :shop
  has_many :conversation_labels, class_name: 'WhatsappConversationLabel', dependent: :delete_all

  COLORS = %w[info success warning critical attention new].freeze
  MAX_PER_SHOP = 50

  DEFAULTS = [
    { system_key: 'order_status', name: 'Order status', color: 'info' },
    { system_key: 'cancel_request', name: 'Cancel request', color: 'critical' },
    { system_key: 'address_change', name: 'Address change', color: 'warning' },
    { system_key: 'return_refund', name: 'Return/refund', color: 'attention' },
    { system_key: 'payment', name: 'Payment', color: 'success' },
    { system_key: 'campaign_reply', name: 'Campaign reply', color: 'new' },
    { system_key: 'notification_reply', name: 'Notification reply', color: 'info' }
  ].freeze
  SYSTEM_KEYS = DEFAULTS.map { |d| d[:system_key] }.freeze

  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_fields

  validates :name, presence: true, length: { maximum: 40 }
  validates :color, inclusion: { in: COLORS }
  validates :system_key, inclusion: { in: SYSTEM_KEYS }, allow_nil: true
  validate :name_unique_in_shop
  validate :within_shop_limit, on: :create

  def self.ensure_defaults!(shop)
    present = where(shop_id: shop.id).where(system_key: SYSTEM_KEYS).pluck(:system_key)
    missing = DEFAULTS.reject { |d| present.include?(d[:system_key]) }
    return if missing.empty?

    now = Time.current
    rows = missing.map do |d|
      { shop_id: shop.id, name: d[:name], color: d[:color], system_key: d[:system_key],
        position: SYSTEM_KEYS.index(d[:system_key]), created_at: now, updated_at: now }
    end
    insert_all(rows)
  end

  def system?
    system_key.present?
  end

  def as_inbox_json
    { 'id' => id, 'name' => name, 'color' => color, 'system_key' => system_key }
  end

  private

  def normalize_fields
    self.name = name.to_s.squish
    self.color = color.to_s.presence || 'info'
  end

  def name_unique_in_shop
    return if name.blank?

    taken = self.class.where(shop_id: shop_id).where('lower(name) = ?', name.downcase).where.not(id: id).exists?
    errors.add(:name, 'is already used by another label') if taken
  end

  def within_shop_limit
    return unless self.class.where(shop_id: shop_id).count >= MAX_PER_SHOP

    errors.add(:base, "You can have up to #{MAX_PER_SHOP} labels")
  end
end
