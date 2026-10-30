class AddPartialShippingKeywordToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :partial_shipping_keyword, :string, default:''
  end
end
