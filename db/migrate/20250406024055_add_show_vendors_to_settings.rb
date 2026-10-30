class AddShowVendorsToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :show_vendors, :string
  end
end
