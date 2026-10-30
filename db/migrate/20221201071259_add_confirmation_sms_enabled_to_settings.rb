class AddConfirmationSmsEnabledToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :confirmation_sms_enabled, :boolean
    add_column :settings, :confirmation_flow_id, :string
  end
end
