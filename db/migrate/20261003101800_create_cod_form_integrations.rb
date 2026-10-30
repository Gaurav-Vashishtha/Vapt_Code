# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.18): per-shop integrations (Google Sheets, Klaviyo, Omnisend, RabbitPay).
class CreateCodFormIntegrations < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_form_integrations, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :provider, null: false
      t.string :status, null: false, default: "disconnected"
      t.jsonb :credentials, null: false, default: {}
      t.jsonb :config, null: false, default: {}
      t.string :last_error
      t.datetime :last_success_at
      t.timestamps null: false
    end

    add_index :cod_form_integrations, %i[shop_id provider], unique: true,
              name: "index_cod_form_integrations_on_shop_id_and_provider", if_not_exists: true
  end
end
