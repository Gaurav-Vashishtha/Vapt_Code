class AddRegisteredAtToWhatsappAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :whatsapp_accounts, :registered_at, :datetime
  end
end
