class AddPrePrimaryButtonColorToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :pre_primary_button_color, :string, default: '#000000'
    add_column :settings, :pre_secondary_button_color, :string, default: '#000000'
    add_column :settings, :pre_primary_button_font_color, :string, default: '#FFFFFF'
    add_column :settings, :pre_secondary_button_font_color, :string, default: '#FFFFFF'
  end
end
