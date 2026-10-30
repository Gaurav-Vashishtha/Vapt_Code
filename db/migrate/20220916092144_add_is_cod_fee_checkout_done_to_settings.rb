class AddIsCodFeeCheckoutDoneToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :is_cod_fee_checkout_done, :boolean
  end
end
