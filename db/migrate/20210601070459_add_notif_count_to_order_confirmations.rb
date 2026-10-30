class AddNotifCountToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :notif_count, :integer, default: 0
  end
end
