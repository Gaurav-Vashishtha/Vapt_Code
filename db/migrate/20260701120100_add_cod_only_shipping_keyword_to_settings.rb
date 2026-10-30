class AddCodOnlyShippingKeywordToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :cod_only_shipping_keyword, :string, default: ""
  end
end
