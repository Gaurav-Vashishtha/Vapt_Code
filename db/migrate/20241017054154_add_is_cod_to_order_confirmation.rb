class AddIsCodToOrderConfirmation < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :is_cod_order, :boolean, default:false
  end
end
