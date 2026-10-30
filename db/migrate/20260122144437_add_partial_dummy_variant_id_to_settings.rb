class AddPartialDummyVariantIdToSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :settings, :partial_dummy_variant_id, :string
  end
end

