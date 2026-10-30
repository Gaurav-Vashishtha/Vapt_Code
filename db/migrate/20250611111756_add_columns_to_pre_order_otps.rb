class AddColumnsToPreOrderOtps < ActiveRecord::Migration[7.0]
  def change
    add_column :pre_order_otps, :shopify_order_ids, :string
    add_column :pre_order_otps, :cart_details, :json, array: true, default: []
    add_column :pre_order_otps, :order_status, :string, default: 'IN_PROGRESS'
  end
end