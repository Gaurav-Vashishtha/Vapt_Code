class AddOrderNumberePrefixToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :order_number_prefix, :string, default:''
  end
end
