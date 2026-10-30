# frozen_string_literal: true

class AddWebhookSourceToAbandonedCarts < ActiveRecord::Migration[7.2]
  def change
    add_column :abandoned_carts, :source,         :string,  default: 'shopify', null: false
    add_column :abandoned_carts, :source_payload, :jsonb,   default: {},        null: false
    add_column :abandoned_carts, :is_anchor,      :boolean, default: false,     null: false
  end
end
