# frozen_string_literal: true

class AddOrderStatsToWhatsappContacts < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      change_table :whatsapp_contacts, bulk: true do |t|
        t.integer :cod_orders_count
        t.integer :prepaid_orders_count
        t.integer :rto_orders_count
        t.integer :returned_orders_count
        t.datetime :last_cod_order_at
        t.datetime :last_unconfirmed_cod_at
        t.datetime :order_stats_synced_at
      end
    end
  end
end
