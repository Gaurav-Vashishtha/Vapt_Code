class AddLightweightSettingsChangedAtToSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :settings, :lightweight_settings_changed_at, :datetime
    add_index :settings, :lightweight_settings_changed_at
  end
end

