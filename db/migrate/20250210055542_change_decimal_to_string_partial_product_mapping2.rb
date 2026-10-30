class ChangeDecimalToStringPartialProductMapping2 < ActiveRecord::Migration[6.0]
  def change
        change_column :partial_product_mappings, :partial_variant_id, :string
  end
end
