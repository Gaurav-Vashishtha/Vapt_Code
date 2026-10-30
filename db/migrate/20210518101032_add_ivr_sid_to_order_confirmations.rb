class AddIvrSidToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :ivr_sid, :string
  end
end
