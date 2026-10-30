class AddDetailsToUninstalledShop < ActiveRecord::Migration[6.0]
  def change
    add_column :uninstalled_shops, :shopify_created_on, :string, default:''
    add_column :uninstalled_shops, :sms, :boolean, default:false
    add_column :uninstalled_shops, :confirmation_sms_enabled, :boolean, default:false
    add_column :uninstalled_shops, :cod_fee_enabled, :boolean, default:false
    add_column :uninstalled_shops, :enable_pre_order_otp, :boolean, default:false
    add_column :uninstalled_shops, :abandoned_cart_enabled, :boolean, default:false
    add_column :uninstalled_shops, :prepaid_enabled, :boolean, default:false
  end
end
