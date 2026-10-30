class AddSourceNameToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :source_name, :string
  end
end
