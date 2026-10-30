class AddIsTaxIncludedWithProductToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :is_tax_included_with_product, :boolean, default:false
  end
end
