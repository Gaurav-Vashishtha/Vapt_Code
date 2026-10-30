class AddPurposeToLeadCollections < ActiveRecord::Migration[7.0]
  def change
    add_column :lead_collections, :purpose, :string, null: false, default: "product_demo"
    add_index :lead_collections, :purpose
  end
end
