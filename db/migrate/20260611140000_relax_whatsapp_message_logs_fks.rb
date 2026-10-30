class RelaxWhatsappMessageLogsFks < ActiveRecord::Migration[7.2]
  # When a merchant disconnects their WABA, we destroy the account row which
  # cascades to its templates. The existing FKs were strict (no ON DELETE rule)
  # so the destroy raised PG::ForeignKeyViolation.
  #
  # New rules:
  #   - whatsapp_account_id  → ON DELETE CASCADE (logs go with the account)
  #   - whatsapp_template_id → ON DELETE SET NULL (logs survive template deletes;
  #                                                template_id is already nullable)
  def up
    if foreign_key_exists?(:whatsapp_message_logs, :whatsapp_templates)
      remove_foreign_key :whatsapp_message_logs, :whatsapp_templates
    end
    if foreign_key_exists?(:whatsapp_message_logs, :whatsapp_accounts)
      remove_foreign_key :whatsapp_message_logs, :whatsapp_accounts
    end

    add_foreign_key :whatsapp_message_logs, :whatsapp_templates, on_delete: :nullify
    add_foreign_key :whatsapp_message_logs, :whatsapp_accounts,  on_delete: :cascade
  end

  def down
    if foreign_key_exists?(:whatsapp_message_logs, :whatsapp_templates)
      remove_foreign_key :whatsapp_message_logs, :whatsapp_templates
    end
    if foreign_key_exists?(:whatsapp_message_logs, :whatsapp_accounts)
      remove_foreign_key :whatsapp_message_logs, :whatsapp_accounts
    end

    add_foreign_key :whatsapp_message_logs, :whatsapp_templates
    add_foreign_key :whatsapp_message_logs, :whatsapp_accounts
  end
end
