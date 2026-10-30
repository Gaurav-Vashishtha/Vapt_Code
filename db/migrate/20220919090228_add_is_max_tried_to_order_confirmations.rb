class AddIsMaxTriedToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :is_max_tried, :boolean
  end
end
