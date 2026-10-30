class CreatePartialProductMapping < ActiveRecord::Migration[6.0]
  def change
    create_table :partial_product_mappings do |t|
      t.string :partial_product_id
      t.decimal :partial_variant_id
      t.string :original_variant_ids, array:true
      t.boolean :is_deleted, default: false
      t.string :shopify_domain
      t.timestamps
    end
  end
end
