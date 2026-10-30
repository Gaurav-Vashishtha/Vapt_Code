# frozen_string_literal: true

class CreateWhatsappAiCreditTransactions < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_ai_credit_transactions do |t|
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.string   :kind, null: false
        t.string   :status, null: false, default: 'completed'
        t.integer  :credits, null: false, default: 0
        t.integer  :balance_after
        t.string   :pack
        t.decimal  :amount_usd, precision: 10, scale: 2
        t.string   :shopify_charge_gid
        t.text     :confirmation_url
        t.bigint   :whatsapp_ai_run_id
        t.string   :note
        t.timestamps
      end
      add_index :whatsapp_ai_credit_transactions, %i[shop_id created_at], name: 'idx_wa_ai_tx_shop_time'
      add_index :whatsapp_ai_credit_transactions, :shopify_charge_gid, unique: true,
                where: 'shopify_charge_gid IS NOT NULL', name: 'idx_wa_ai_tx_charge'
      add_index :whatsapp_ai_credit_transactions, %i[shop_id status], where: "status = 'pending'",
                name: 'idx_wa_ai_tx_pending'
    end
  end
end
