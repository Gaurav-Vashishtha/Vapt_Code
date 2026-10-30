class AddCartHashToMappings < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_product_mappings, :cart_hash, :string
    
    add_index :partial_product_mappings, [:shopify_domain, :cart_hash]
    add_index :partial_product_mappings, [:shopify_domain, :cart_hash, :session_id], 
              name: 'index_mappings_on_domain_hash_session'
    add_index :partial_product_mappings, [:shopify_domain, :session_id, :cart_rule_id], 
              name: 'index_mappings_on_domain_session_cart_rule'
  end
end
