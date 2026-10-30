class AddEmailAddressesToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :email_addresses, :string
  end
end
