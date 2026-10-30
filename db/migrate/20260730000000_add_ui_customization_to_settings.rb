class AddUiCustomizationToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :ui_customization, :jsonb, default: {}, null: false
  end
end
