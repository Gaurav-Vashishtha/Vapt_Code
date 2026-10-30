class AddRetryToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :retry, :integer ,default: -1
    add_column :settings, :retry_template, :string 
  end
end
