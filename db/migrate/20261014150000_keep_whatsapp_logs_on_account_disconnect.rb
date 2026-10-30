# frozen_string_literal: true

# Disconnecting a WhatsApp (BSP) number used to delete its message logs and customer replies
# (ON DELETE CASCADE), wiping the merchant's activity history and any not-yet-billed sends.
# Logs and replies now outlive the number: the account reference is cleared instead.
class KeepWhatsappLogsOnAccountDisconnect < ActiveRecord::Migration[7.2]
  def up
    remove_foreign_key :whatsapp_message_logs, :whatsapp_accounts
    change_column_null :whatsapp_message_logs, :whatsapp_account_id, true
    add_foreign_key :whatsapp_message_logs, :whatsapp_accounts, on_delete: :nullify

    remove_foreign_key :whatsapp_inbound_messages, :whatsapp_accounts
    change_column_null :whatsapp_inbound_messages, :whatsapp_account_id, true
    add_foreign_key :whatsapp_inbound_messages, :whatsapp_accounts, on_delete: :nullify
  end

  def down
    remove_foreign_key :whatsapp_message_logs, :whatsapp_accounts
    add_foreign_key :whatsapp_message_logs, :whatsapp_accounts, on_delete: :cascade
    remove_foreign_key :whatsapp_inbound_messages, :whatsapp_accounts
    add_foreign_key :whatsapp_inbound_messages, :whatsapp_accounts, on_delete: :cascade
    # Columns stay nullable: rows from disconnected numbers may already have a NULL account.
  end
end
