class WhatsappOptOut < ApplicationRecord
  belongs_to :shop

  validates :phone_normalized, presence: true

  def self.opted_out?(shop_id, phone_normalized)
    return false if phone_normalized.blank?
    where(shop_id: shop_id, phone_normalized: phone_normalized).exists?
  end

  def self.opted_out_set(shop_id)
    where(shop_id: shop_id).pluck(:phone_normalized).to_set
  end

  def self.record!(shop_id:, phone_normalized:, reason:, source: nil)
    return if phone_normalized.blank?
    upsert(
      { shop_id: shop_id, phone_normalized: phone_normalized, reason: reason, source: source,
        opted_out_at: Time.current, created_at: Time.current, updated_at: Time.current },
      unique_by: %i[shop_id phone_normalized]
    )
  end
end
