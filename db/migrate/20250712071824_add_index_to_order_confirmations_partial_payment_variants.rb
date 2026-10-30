class AddIndexToOrderConfirmationsPartialPaymentVariants < ActiveRecord::Migration[7.2]
  def change
        add_column :order_confirmations, :partial_payment_variants, :string, default:''
  end
end
