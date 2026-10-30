class AddAutoVerifyToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :auto_verify, :boolean
  end
end
