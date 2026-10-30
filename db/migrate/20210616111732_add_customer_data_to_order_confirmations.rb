class AddCustomerDataToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :customer_email, :string
    add_column :order_confirmations, :currency, :string
    add_column :order_confirmations, :prepaid_link, :string
    add_column :order_confirmations, :draft_payment_gateway, :string
    add_column :order_confirmations, :draft_order_id, :string
    add_column :order_confirmations, :draft_order_uuid, :string
  end
end
