class AddLastShippingStatusPulledToShops < ActiveRecord::Migration[7.0]
  def change
    add_column :shops, :last_shipping_status_pulled, :datetime
    add_index :shops, :last_shipping_status_pulled
  end
end
