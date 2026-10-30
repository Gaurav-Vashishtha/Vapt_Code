class AddCodFeeShippingKeywordToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :cod_fee_shipping_keyword, :string, default:''
  end
end
