class AddDefaultExpiryTime < ActiveRecord::Migration[6.0]
  def change
    change_column :settings, :prepaid_expiry, :integer, :default => 1440
  end
end
