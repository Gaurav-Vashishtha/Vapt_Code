class AddIsCodFeeEmailDoneToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :is_cod_fee_email_done, :boolean
  end
end
