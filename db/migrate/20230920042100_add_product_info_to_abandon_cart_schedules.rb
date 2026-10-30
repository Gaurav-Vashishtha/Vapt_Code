class AddProductInfoToAbandonCartSchedules < ActiveRecord::Migration[6.0]
  def change
    add_column :abandon_cart_schedules, :product_info, :string, default:''
  end
end
