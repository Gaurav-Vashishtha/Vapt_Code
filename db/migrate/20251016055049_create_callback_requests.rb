# db/migrate/[timestamp]_create_callback_requests.rb
class CreateCallbackRequests < ActiveRecord::Migration[7.0]
  def change
    create_table :callback_requests do |t|
      t.string :shop_domain, null: false
      t.string :name, null: false
      t.string :phone_number, null: false
      t.string :email, null: false
      t.string :preferred_time
      t.string :timezone
      t.text :notes
      t.string :status, default: 'pending'
      t.json :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :callback_requests, :shop_domain
    add_index :callback_requests, [:shop_domain, :created_at]
    add_index :callback_requests, :status
  end
end