class CreateWallets < ActiveRecord::Migration[7.0]
  def change
    create_table :wallets do |t|
      t.decimal :total_balance, precision: 10, scale: 2, null: false, default: 1.0
      t.decimal :balance_used, precision: 10, scale: 2, null: false, default: 0.0
      t.string :shopify_domain, null: false

      t.timestamps
    end

    # If you want to add an index for quick lookups by shopify_domain
    add_index :wallets, :shopify_domain, unique: true
  end
end