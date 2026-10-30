# frozen_string_literal: true

class AddTargetAndUninstalledShopToEmailRules < ActiveRecord::Migration[7.0]
  def change
    add_column :email_rules, :target, :string, default: "shops", null: false

    # scheduled_emails: allow either shop_id or uninstalled_shop_id
    add_column :scheduled_emails, :uninstalled_shop_id, :bigint
    change_column_null :scheduled_emails, :shop_id, true

    # Replace single unique index with two partial unique indexes
    remove_index :scheduled_emails, name: "index_scheduled_emails_on_email_rule_id_and_shop_id"
    add_index :scheduled_emails, [:email_rule_id, :shop_id],
              unique: true,
              name: "index_scheduled_emails_on_rule_and_shop_id",
              where: "shop_id IS NOT NULL"
    add_index :scheduled_emails, [:email_rule_id, :uninstalled_shop_id],
              unique: true,
              name: "index_scheduled_emails_on_rule_and_uninstalled_shop_id",
              where: "uninstalled_shop_id IS NOT NULL"
  end
end
