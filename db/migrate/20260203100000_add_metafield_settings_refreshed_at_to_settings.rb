# frozen_string_literal: true

class AddMetafieldSettingsRefreshedAtToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :metafield_settings_refreshed_at, :datetime
  end
end
