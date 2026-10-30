class AddHideProductVariantIdToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :hide_product_variant_ids, :string, default:''
  end
end
