class AddAutoDeleteToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :auto_delete, :boolean
  end
end
