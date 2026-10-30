class AddPreBlockPhoneToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :pre_block_phone, :string, default:''
  end
end
