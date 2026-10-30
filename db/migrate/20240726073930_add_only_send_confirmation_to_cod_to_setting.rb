class AddOnlySendConfirmationToCodToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :only_send_confirmation_to_cod, :boolean, default:false
  end
end
