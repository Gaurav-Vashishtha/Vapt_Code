class AddTestVariantIdToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :test_variant_id, :string
  end
end
