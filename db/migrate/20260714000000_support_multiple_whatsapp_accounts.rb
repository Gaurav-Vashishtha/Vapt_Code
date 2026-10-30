class SupportMultipleWhatsappAccounts < ActiveRecord::Migration[7.2]
  def up
    # A shop can now connect several numbers — drop the one-account-per-shop
    # unique index, keep a plain lookup index.
    remove_index :whatsapp_accounts, name: 'index_whatsapp_accounts_on_shop_id'
    add_index :whatsapp_accounts, :shop_id, name: 'index_whatsapp_accounts_on_shop_id'

    # Exactly one account per shop is the default (used when an event has no
    # explicit routing). Merchant-facing label to tell numbers apart.
    add_column :whatsapp_accounts, :is_default, :boolean, default: false, null: false
    add_column :whatsapp_accounts, :label, :string

    # phone_number_id is globally unique at Meta and is the key we route
    # inbound/status webhooks by. We keep the existing NON-unique lookup index
    # (adding a unique constraint could fail to build on pre-existing duplicate
    # test rows) and enforce uniqueness at the application layer instead
    # (WhatsappAccount validation) so a bad migration can't take prod down.

    # Every existing account is its shop's default (there's one per shop today).
    execute 'UPDATE whatsapp_accounts SET is_default = true'

    # A binding now records WHICH number the event sends from. Nullable — null
    # means "use the shop default", which is how every existing binding behaves.
    # FK nullifies on account delete, so removing a number safely reverts its
    # events to the default instead of dangling.
    add_reference :whatsapp_template_bindings, :whatsapp_account, null: true, index: true,
                  foreign_key: { on_delete: :nullify }

    # Backfill: point each existing binding at its bound template's account, so
    # current routing is explicit and unchanged.
    execute <<~SQL.squish
      UPDATE whatsapp_template_bindings b
      SET whatsapp_account_id = t.whatsapp_account_id
      FROM whatsapp_templates t
      WHERE b.whatsapp_template_id = t.id
    SQL
  end

  def down
    remove_reference :whatsapp_template_bindings, :whatsapp_account, foreign_key: true

    remove_column :whatsapp_accounts, :label
    remove_column :whatsapp_accounts, :is_default

    remove_index :whatsapp_accounts, name: 'index_whatsapp_accounts_on_shop_id'
    add_index :whatsapp_accounts, :shop_id, unique: true, name: 'index_whatsapp_accounts_on_shop_id'
  end
end
