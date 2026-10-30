class AddPhonePickOrderToShops < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :phone_pick_order, :string
  end
end
