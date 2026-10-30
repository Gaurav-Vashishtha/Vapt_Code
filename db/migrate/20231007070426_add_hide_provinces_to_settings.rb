class AddHideProvincesToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :hide_provinces, :string, default: ''
    add_column :settings, :show_provinces, :string, default: ''
  end
end
