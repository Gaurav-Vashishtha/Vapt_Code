class CreateDiscounts < ActiveRecord::Migration[7.2]
  def change
    create_table :discounts do |t|
      t.references :shop, null: false, foreign_key: true, index: true

      # Merchant-facing config
      t.string  :title, null: false
      t.string  :method, null: false               # 'code' | 'automatic'
      t.string  :code                              # null for automatic
      t.string  :discount_type, null: false        # 'amount_off' | 'percentage' | 'buy_x_get_y'
      t.decimal :value, precision: 10, scale: 2     # percentage (as entered) or fixed amount

      # Targeting
      t.string  :applies_to, null: false, default: 'all'   # 'all' | 'products' | 'collections'
      t.jsonb   :product_gids,    null: false, default: []
      t.jsonb   :collection_gids, null: false, default: []

      # BXGY (only when discount_type = 'buy_x_get_y')
      t.jsonb   :bxgy_config, null: false, default: {}

      # Requirements / limits / schedule
      t.string   :minimum_requirement_type          # null | 'subtotal' | 'quantity'
      t.decimal  :minimum_requirement_value, precision: 10, scale: 2
      t.integer  :usage_limit                        # code only; null = unlimited
      t.boolean  :once_per_customer, null: false, default: false
      t.datetime :starts_at
      t.datetime :ends_at

      # Combinations
      t.boolean :combines_with_order,    null: false, default: true
      t.boolean :combines_with_product,  null: false, default: false
      t.boolean :combines_with_shipping, null: false, default: true

      # Widget display metadata (ours, not Shopify's)
      t.boolean :widget_enabled, null: false, default: true
      t.string  :headline
      t.string  :unlock_text
      t.integer :display_order, null: false, default: 0

      # Shopify sync state
      t.string  :shopify_gid
      t.string  :sync_status, null: false, default: 'pending'   # 'pending' | 'synced' | 'failed'
      t.text    :sync_error
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :discounts, [:shop_id, :code], unique: true, where: "code IS NOT NULL"
    add_index :discounts, [:shop_id, :is_active]
    add_index :discounts, [:shop_id, :widget_enabled]
    add_index :discounts, :shopify_gid
  end
end
