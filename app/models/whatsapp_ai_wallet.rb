# frozen_string_literal: true

class WhatsappAiWallet < ApplicationRecord
  belongs_to :shop

  PACKS = {
    'pack_1k' => { 'credits' => 1_000, 'price_usd' => 10.0 },
    'pack_5k' => { 'credits' => 5_000, 'price_usd' => 40.0 },
    'pack_15k' => { 'credits' => 15_000, 'price_usd' => 99.0 }
  }.freeze
  FREE_CREDITS = 100
  LOW_BALANCE = 50

  validates :auto_recharge_pack, inclusion: { in: PACKS.keys }, allow_nil: true

  def self.for(shop)
    find_or_create_by!(shop_id: shop.id)
  rescue ActiveRecord::RecordNotUnique
    find_by!(shop_id: shop.id)
  end

  def self.pack(key)
    PACKS[key.to_s]
  end

  def low?
    balance < LOW_BALANCE
  end

  def as_api_json
    {
      'balance' => balance,
      'lifetime_purchased' => lifetime_purchased,
      'lifetime_used' => lifetime_used,
      'free_granted' => free_granted_at.present?,
      'free_credits' => FREE_CREDITS,
      'low' => low?,
      'low_balance' => LOW_BALANCE,
      'auto_recharge' => auto_recharge,
      'auto_recharge_pack' => auto_recharge_pack,
      'auto_recharge_error' => auto_recharge_failed_at.present? ? auto_recharge_error : nil,
      'packs' => PACKS.map { |key, p| p.merge('key' => key) }
    }
  end
end
