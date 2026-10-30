class AddTokenTitleToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :pre_v2_title, :string , default:''
    add_column :settings, :store_front_token, :string , default:''
  end
end
