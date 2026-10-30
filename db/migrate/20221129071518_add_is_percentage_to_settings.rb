class AddIsPercentageToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :is_percentage, :boolean
  end
end
