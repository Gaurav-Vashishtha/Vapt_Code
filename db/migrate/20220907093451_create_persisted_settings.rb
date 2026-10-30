class CreatePersistedSettings < ActiveRecord::Migration[6.0]
  def change
    create_table :persisted_settings do |t|
      t.integer :test_order_count
      t.string  :shopify_domain
      t.timestamps
    end
  end
end
