class AddDefaultValue < ActiveRecord::Migration[6.0]
  def change
    change_column :settings, :phone_numbers, :string, :default => ''
  end
end
