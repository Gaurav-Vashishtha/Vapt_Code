class AddPrepaidExpiryToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :prepaid_expiry, :integer
    add_column :settings, :prepaid_discount, :float
  end
end
