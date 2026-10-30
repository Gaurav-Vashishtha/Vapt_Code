class AddAbandonedCart < ActiveRecord::Migration[6.0]
  def change
      create_table :abandoned_carts do |t|
      t.string :checkout_id
      t.string :url
      t.boolean :status
      t.string :notes
      t.string :sid
      t.string :phone
      t.string :country_code
      t.string :shopify_created_at
      t.string :type
      t.boolean :is_charged

      t.references :shop, foreign_key: true
      t.timestamps
    end
  end
end
