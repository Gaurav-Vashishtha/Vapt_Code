class AddWhatsappEnabledToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :whatsapp_enabled, :boolean, :default => true
  end
end
