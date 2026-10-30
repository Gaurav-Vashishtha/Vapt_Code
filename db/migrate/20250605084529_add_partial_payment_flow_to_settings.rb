class AddPartialPaymentFlowToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :partial_payment_flow, :string, default: 'NEW_ORDER'
    add_column :settings, :pre_v2_show_send_code, :boolean, default: true
    add_column :settings, :pre_v2_partial_tax_text, :string, default: 'Taxes computed later'
  end
end
