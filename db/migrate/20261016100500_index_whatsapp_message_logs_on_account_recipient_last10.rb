# frozen_string_literal: true

class IndexWhatsappMessageLogsOnAccountRecipientLast10 < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    # A killed CONCURRENTLY build leaves an INVALID index that if_not_exists would then skip forever.
    reversible { |dir| dir.up { execute("DROP INDEX CONCURRENTLY IF EXISTS idx_wa_logs_account_recipient_last10") if invalid_index?('idx_wa_logs_account_recipient_last10') } }

    add_index :whatsapp_message_logs,
              "whatsapp_account_id, right(regexp_replace(recipient, '\\D', '', 'g'), 10), created_at",
              name: 'idx_wa_logs_account_recipient_last10', algorithm: :concurrently, if_not_exists: true
  end
end
