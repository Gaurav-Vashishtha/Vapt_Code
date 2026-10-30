class AddSenderToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :sender, :string, default:''
  end
end
