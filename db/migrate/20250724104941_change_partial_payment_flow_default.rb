class ChangePartialPaymentFlowDefault < ActiveRecord::Migration[7.2]
  def change
        change_column_default :settings, :partial_payment_flow, from: "NEW_ORDER", to: "SAME_ORDER"
  end
end
