class AddShowProductIdsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :show_product_ids, :string, default:''
  end
end