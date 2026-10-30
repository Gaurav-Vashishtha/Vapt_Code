class AddDebugToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :debug, :boolean, default: false
  end
end
