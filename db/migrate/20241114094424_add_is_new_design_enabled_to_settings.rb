class AddIsNewDesignEnabledToSettings < ActiveRecord::Migration[6.0]
  def change
        add_column :settings, :pre_is_new_design_enabled, :boolean , default:false
  end
end
