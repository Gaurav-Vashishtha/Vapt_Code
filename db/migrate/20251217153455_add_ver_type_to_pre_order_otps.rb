class AddVerTypeToPreOrderOtps < ActiveRecord::Migration[7.2]
  def change
    add_column :pre_order_otps, :ver_type, :string, default: 'SMS', null: false
    add_index :pre_order_otps, :ver_type
  end
end

