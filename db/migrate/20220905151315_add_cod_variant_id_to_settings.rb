class AddCodVariantIdToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :cod_variant_id, :string
  end
end
