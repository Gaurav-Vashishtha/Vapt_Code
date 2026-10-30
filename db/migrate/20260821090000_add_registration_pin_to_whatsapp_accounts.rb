class AddRegistrationPinToWhatsappAccounts < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    return if column_exists?(:whatsapp_accounts, :registration_pin)

    # ALTER TABLE needs ACCESS EXCLUSIVE. If anything else holds a conflicting
    # lock on whatsapp_accounts (a long SELECT, an idle-in-transaction Sidekiq
    # connection), this waits — and while it waits every other query on the
    # table queues behind it, which is how a metadata-only add_column takes the
    # app down. Fail the release fast instead.
    execute "SET lock_timeout = '5s'"
    add_column :whatsapp_accounts, :registration_pin, :text
  ensure
    execute "SET lock_timeout = DEFAULT"
  end

  def down
    return unless column_exists?(:whatsapp_accounts, :registration_pin)

    execute "SET lock_timeout = '5s'"
    remove_column :whatsapp_accounts, :registration_pin
  ensure
    execute "SET lock_timeout = DEFAULT"
  end
end
