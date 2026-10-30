class AddSelectedCountriesToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :selected_countries, :string , default:''
  end
end
