class AddPartialPaymentFlowVersionToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :partial_payment_flow_version, :integer, default: 1
  end
end

