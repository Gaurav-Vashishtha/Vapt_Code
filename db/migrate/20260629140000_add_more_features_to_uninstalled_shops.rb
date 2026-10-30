class AddMoreFeaturesToUninstalledShops < ActiveRecord::Migration[7.2]
  def change
    add_column :uninstalled_shops, :partial_payment_enabled, :boolean, default: false
    add_column :uninstalled_shops, :ac_whatsapp, :boolean, default: false
    add_column :uninstalled_shops, :bsp_integrated, :boolean, default: false
    add_column :uninstalled_shops, :cod_show_hide_enabled, :boolean, default: false
  end
end
