class AddIsLoginEnabledToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :pre_is_login_enabled, :boolean , default:false
  end
end
