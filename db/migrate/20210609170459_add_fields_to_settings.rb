class AddFieldsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :provider, :string
    add_column :settings, :provider_api_key, :text
    add_column :settings, :provider_sender_id, :string
  end
end
