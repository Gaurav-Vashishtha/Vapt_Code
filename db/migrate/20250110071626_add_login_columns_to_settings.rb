class AddLoginColumnsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :pre_v2_theme, :string, default:'theme5'
    add_column :settings, :pre_v2_show_order_summary, :boolean, default:false
  end
end
