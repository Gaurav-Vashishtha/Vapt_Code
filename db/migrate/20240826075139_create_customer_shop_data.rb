class CreateCustomerShopData < ActiveRecord::Migration[6.0]
  def change
    create_table :customer_shop_data do |t|
      t.string :shopify_domain
      t.string :shopify_customer_id
      t.float :order_value
      t.float :last_order_value
      t.integer :order_count
      t.boolean :verified_email

      t.timestamps
      t.references :customer, foreign_key: true
    end
  end
end
