class ChangeDeafultCodFees < ActiveRecord::Migration[6.0]
  def change
  	change_column :settings, :cod_fees, :decimal, :default => 5.0
  	change_column :settings, :cod_label, :string, :default => 'Cash on delivery fees'
  	change_column :settings, :cod_instrutction, :string, :default => 'Please pay additional COD fees while collecting the delivery.'
  end
end
