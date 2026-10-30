class AddAmountToShowAndSubHeadingToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :amount_to_show, :string, default:''
    add_column :partial_rule_sets, :sub_heading, :string, default:''
  end
end
