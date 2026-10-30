class AddCustomScriptToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :custom_script, :string
  end
end
