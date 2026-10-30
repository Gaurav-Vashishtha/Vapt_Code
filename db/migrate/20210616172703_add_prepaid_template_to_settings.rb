class AddPrepaidTemplateToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :prepaid_template, :string,
               default: 'convert your order to prepaid by clicking the link. {{link}}'
  end
end
