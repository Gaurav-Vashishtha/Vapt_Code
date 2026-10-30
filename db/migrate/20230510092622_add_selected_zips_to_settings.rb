class AddSelectedZipsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :selected_zips, :string , default:''
    add_column :settings, :selected_product_ids, :string , default:''
  end
end
