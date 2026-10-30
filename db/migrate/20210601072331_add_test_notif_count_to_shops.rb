class AddTestNotifCountToShops < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :test_notif_count, :integer, default: 0
  end
end
