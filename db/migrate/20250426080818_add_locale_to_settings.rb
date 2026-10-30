class AddLocaleToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :selected_locale, :string, default:''
  end
end
