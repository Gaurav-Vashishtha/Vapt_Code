class ChangeDecimalToStringPartialProductMapping < ActiveRecord::Migration[6.0]
  def change
     def up
      change_column :partial_product_mappings, :partial_variant_id, :string
    end

  def down
    change_column :partial_product_mappings, :partial_variant_id, :decimal
  end
  end
end
