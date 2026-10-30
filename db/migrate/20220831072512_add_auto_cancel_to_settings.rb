class AddAutoCancelToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :auto_cancel, :integer ,default: -1
  end
end
