class CreateIntegrations < ActiveRecord::Migration[6.0]
  def change
    create_table :integrations do |t|
      t.boolean :active
      t.string :provider
      t.text :provider_api_key
      t.string :provider_sender_id
      t.references :shop, null: false, foreign_key: true
    end
  end
end
