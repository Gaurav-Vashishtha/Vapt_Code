class PreShowSkipBtnToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :pre_show_skip_btn, :boolean, default:false
  end
end
