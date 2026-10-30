# frozen_string_literal: true

class WhatsappSavedReply < ApplicationRecord
  belongs_to :shop

  MAX_PER_SHOP = 200
  MAX_BODY_LENGTH = 4096
  SHORTCUT_FORMAT = /\A[[:alnum:]_-]+\z/

  scope :ordered, -> { order(usage_count: :desc, title: :asc, id: :asc) }

  before_validation :normalize_fields

  validates :title, presence: true, length: { maximum: 60 }
  validates :shortcut, presence: true, length: { maximum: 30 },
                       format: { with: SHORTCUT_FORMAT, message: 'can only use letters, numbers, - and _' }
  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
  validate :shortcut_unique_in_shop
  validate :within_shop_limit, on: :create

  def record_use!
    now = Time.current
    self.class.where(id: id).update_all(['usage_count = usage_count + 1, last_used_at = ?, updated_at = ?', now, now])
    reload
  end

  def as_inbox_json
    { 'id' => id, 'title' => title, 'shortcut' => shortcut, 'body' => body, 'usage_count' => usage_count }
  end

  private

  def normalize_fields
    self.title = title.to_s.squish
    self.shortcut = shortcut.to_s.strip.delete_prefix('/').downcase
    self.body = body.to_s.strip
  end

  def shortcut_unique_in_shop
    return if shortcut.blank?

    taken = self.class.where(shop_id: shop_id).where('lower(shortcut) = ?', shortcut.downcase).where.not(id: id).exists?
    errors.add(:shortcut, 'is already used by another saved reply') if taken
  end

  def within_shop_limit
    return unless self.class.where(shop_id: shop_id).count >= MAX_PER_SHOP

    errors.add(:base, "You can have up to #{MAX_PER_SHOP} saved replies")
  end
end
