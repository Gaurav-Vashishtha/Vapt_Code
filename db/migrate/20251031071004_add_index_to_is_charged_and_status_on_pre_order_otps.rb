class AddIndexToIsChargedAndStatusOnPreOrderOtps < ActiveRecord::Migration[7.2]
  def change
    # Optimize queries filtering by shop_id, is_charged IS NULL, and status
    # Used in DynamicChargeJob for charging uncharged pre_order_otps
    # Using partial index since query always checks for is_charged IS NULL
    add_index :pre_order_otps, [:shop_id, :status],
              name: 'idx_pre_order_otps_charging_queries',
              where: 'is_charged IS NULL'
  end
end
