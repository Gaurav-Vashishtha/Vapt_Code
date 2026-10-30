class CreateCustomer < ActiveRecord::Migration[6.0]
  def change
    create_table :customers do |t|
      t.string :phone
      t.string :email
      t.string :first_name
      t.string :last_name
      t.string :tags
      t.string :currency
      t.timestamps
    end
  end
end
