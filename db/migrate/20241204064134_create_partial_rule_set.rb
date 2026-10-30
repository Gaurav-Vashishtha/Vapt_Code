class CreatePartialRuleSet < ActiveRecord::Migration[6.0]
  def change
    create_table :partial_rule_sets do |t|
      t.string :rule_name
      t.decimal :amount
      t.string :amount_type
      t.string :product_ids, array:true
      t.boolean :is_all, default: false
      t.boolean :is_enabled, default: true
      t.timestamps
      t.references :shop, foreign_key: true
    end
  end
end
