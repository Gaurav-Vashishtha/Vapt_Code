class AddEnableShippingCodFeesToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :enable_shipping_cod_fees, :boolean, default:false
  end
end
