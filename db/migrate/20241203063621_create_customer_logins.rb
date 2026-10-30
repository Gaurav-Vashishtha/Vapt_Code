class CreateCustomerLogins < ActiveRecord::Migration[6.0]
  def change
    create_table :customer_logins do |t|
      t.string :shopify_customer_id
      t.string :phone
      t.string :email
      t.string :password
      t.string :shopify_domain
      t.timestamps
    end
  end
end
