class AddWhatsappIntegrationFieldsToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :last_whatsapp_integration_request_at, :datetime
    add_column :settings, :whatsapp_integration_requests_count, :integer, default: 0
  end
end
