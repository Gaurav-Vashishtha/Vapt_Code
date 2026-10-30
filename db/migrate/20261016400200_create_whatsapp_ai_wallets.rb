# frozen_string_literal: true

class CreateWhatsappAiWallets < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_ai_wallets do |t|
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
        t.integer  :balance, null: false, default: 0
        t.integer  :lifetime_purchased, null: false, default: 0
        t.integer  :lifetime_used, null: false, default: 0
        t.datetime :free_granted_at
        t.boolean  :auto_recharge, null: false, default: false
        t.string   :auto_recharge_pack
        t.datetime :auto_recharge_failed_at
        t.string   :auto_recharge_error
        t.timestamps
      end
    end
  end
end
