class EnsureOrderMetrics < ActiveRecord::Migration[7.2]
  def up
    create_table :order_metrics, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :order_id, null: false
      t.bigint :order_confirmation_id
      t.string :order_name
      t.datetime :ordered_at, null: false
      t.string :currency
      t.boolean :is_cod, null: false, default: false
      t.decimal :total_price, precision: 12, scale: 2, null: false, default: 0
      t.decimal :original_total, precision: 12, scale: 2, null: false, default: 0
      t.decimal :discount_total, precision: 12, scale: 2, null: false, default: 0
      t.jsonb :discounts, null: false, default: []
      t.decimal :prepaid_discount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :cod_fee, precision: 12, scale: 2, null: false, default: 0
      t.string :cod_fee_source
      t.boolean :is_partial, null: false, default: false
      t.decimal :partial_upfront, precision: 12, scale: 2, null: false, default: 0
      t.boolean :is_converted_prepaid, null: false, default: false
      t.string :converted_from_order_id
      t.boolean :is_otp_verified, null: false, default: false
      t.boolean :is_cod_form, null: false, default: false
      t.boolean :is_ac_recovered, null: false, default: false
      t.string :widget_session_id
      t.string :delivery_status, null: false, default: "unfulfilled"
      t.datetime :delivered_at
      t.datetime :rto_at
      t.timestamps
    end

    add_index :order_metrics, [:shop_id, :order_id], unique: true, if_not_exists: true
    add_index :order_metrics, [:shop_id, :ordered_at], if_not_exists: true
    add_index :order_metrics, [:shop_id, :delivery_status, :ordered_at], name: "idx_order_metrics_delivery", if_not_exists: true
    add_index :order_metrics, [:shop_id, :ordered_at], where: "is_converted_prepaid", name: "idx_order_metrics_converted", if_not_exists: true
    add_index :order_metrics, [:shop_id, :ordered_at], where: "is_ac_recovered", name: "idx_order_metrics_ac_recovered", if_not_exists: true
    add_index :order_metrics, [:shop_id, :ordered_at], where: "is_partial", name: "idx_order_metrics_partial", if_not_exists: true
    add_index :order_metrics, [:shop_id, :ordered_at], where: "prepaid_discount > 0", name: "idx_order_metrics_prepaid_discount", if_not_exists: true
    add_index :order_metrics, [:shop_id, :ordered_at], where: "cod_fee > 0", name: "idx_order_metrics_cod_fee", if_not_exists: true
    add_index :order_metrics, [:shop_id, :ordered_at], where: "is_otp_verified", name: "idx_order_metrics_otp_verified", if_not_exists: true
    add_index :order_metrics, [:shop_id, :ordered_at], where: "is_cod_form", name: "idx_order_metrics_cod_form", if_not_exists: true
  end

  def down
  end
end
