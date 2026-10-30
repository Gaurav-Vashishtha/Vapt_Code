class AddPrepaidStatusToOrderConfirmation < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :prepaid_status, :string, default:''
  end
end
