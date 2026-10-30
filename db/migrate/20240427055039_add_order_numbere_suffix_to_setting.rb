class AddOrderNumbereSuffixToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :order_number_suffix, :string , default:''
  end
end
