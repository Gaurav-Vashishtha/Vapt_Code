class AddPrepaidColumns < ActiveRecord::Migration[6.0]
  def change
        add_column :settings, :prepaid_amount_type, :string, :default => 'FULL'
    add_column :settings, :prepaid_token_amount, :decimal, :default => 0.0
    add_column :settings, :prepaid_discount_type, :string, :default => 'FLAT'
  end
end
