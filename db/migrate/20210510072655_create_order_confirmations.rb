class CreateOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    create_table :order_confirmations do |t|
      t.string :order_id
      t.string :order_amount
      t.string :customer_name
      t.string :customer_number
      t.string :status
      t.datetime :confirmed_at
      t.references :shop, null: false, foreign_key: true

      t.timestamps
    end
  end
end
