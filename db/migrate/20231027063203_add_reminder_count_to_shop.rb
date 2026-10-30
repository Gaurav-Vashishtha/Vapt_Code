class AddReminderCountToShop < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :reminder_count, :integer, default:0
  end
end
