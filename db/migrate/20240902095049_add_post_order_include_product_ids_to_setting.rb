class AddPostOrderIncludeProductIdsToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :post_order_include_product_ids, :string , default:''
  end
end
