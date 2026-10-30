class AddShowCancelButtonToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :show_cancel_button, :boolean
  end
end
