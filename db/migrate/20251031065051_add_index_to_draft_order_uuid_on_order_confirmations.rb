class AddIndexToDraftOrderUuidOnOrderConfirmations < ActiveRecord::Migration[7.2]
  def change
    add_index :order_confirmations, :draft_order_uuid
  end
end
