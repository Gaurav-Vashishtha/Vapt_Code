class AddPrepaidEnabledToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :prepaid_enabled, :boolean
  end
end
