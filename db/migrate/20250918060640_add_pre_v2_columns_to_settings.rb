# db/migrate/[TIMESTAMP]_add_pre_v2_columns_to_settings.rb
class AddPreV2ColumnsToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :pre_v2_overwrite_popup_condition, :integer, default: 0
    add_column :settings, :pre_v2_cart_drawer_layout_selectors, :string, default: ''
  end
end