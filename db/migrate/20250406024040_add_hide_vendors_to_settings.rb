class AddHideVendorsToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :hide_vendors, :string
  end
end
