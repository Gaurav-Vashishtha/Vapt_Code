class AddDigestToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :digest, :string
    add_index :order_confirmations, :digest
  end
end
