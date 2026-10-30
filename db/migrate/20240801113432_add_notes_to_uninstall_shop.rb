class AddNotesToUninstallShop < ActiveRecord::Migration[6.0]
  def change
    add_column :uninstalled_shops, :notes, :string, default:''
  end
end
