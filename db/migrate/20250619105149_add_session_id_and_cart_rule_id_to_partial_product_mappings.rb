class AddSessionIdAndCartRuleIdToPartialProductMappings < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_product_mappings, :session_id, :string, default:''
    add_column :partial_product_mappings, :cart_rule_id, :bigint, default:0
  end
end
