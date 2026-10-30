class AddShippingStatusToOrderConfirmations < ActiveRecord::Migration[7.0]
  def change
    add_column :order_confirmations, :shipping_status, :string
    add_index :order_confirmations, [:shop_id, :shipping_status, :created_at], name: "idx_oc_shop_shipping_status_created_at"
  end
end
