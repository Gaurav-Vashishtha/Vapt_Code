class AddLockedToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :locked, :boolean
  end
end
