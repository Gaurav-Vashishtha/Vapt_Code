class AddCodFees < ActiveRecord::Migration[6.0]
  def change
  	add_column :settings, :cod_fee_enabled, :boolean
    add_column :settings, :cod_fees, :decimal
    add_column :settings, :cod_label, :string
    add_column :settings, :cod_description, :string
    add_column :settings, :cod_instrutction, :string
  end
end
