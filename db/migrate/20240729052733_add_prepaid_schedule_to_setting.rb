class AddPrepaidScheduleToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :prepaid_schedule, :string, default:''
  end
end
