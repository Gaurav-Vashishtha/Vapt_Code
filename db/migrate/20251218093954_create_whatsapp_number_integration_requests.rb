class CreateWhatsappNumberIntegrationRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_number_integration_requests do |t|
      t.string :shop_domain, null: false
      t.string :email, null: false
      t.string :phone_number, null: false
      t.string :preferred_time
      t.string :status, default: 'pending'
      t.json :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :whatsapp_number_integration_requests, :shop_domain
    add_index :whatsapp_number_integration_requests, [:shop_domain, :created_at]
    add_index :whatsapp_number_integration_requests, :status
  end
end
