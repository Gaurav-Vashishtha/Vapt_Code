class AddThrottlingIndices < ActiveRecord::Migration[7.2]
  def change
    add_index :pre_order_otps, :phone
    
    # Add composite indices for better performance on time-range queries
    add_index :pre_order_otps, [:ip_address, :created_at]
    add_index :pre_order_otps, [:device_id, :created_at]
    add_index :pre_order_otps, [:phone, :created_at]
  end
end
