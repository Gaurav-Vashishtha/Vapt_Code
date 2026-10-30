class AddPrepaidNotifToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :prepaid_notif, :boolean, default: true
  end
end
