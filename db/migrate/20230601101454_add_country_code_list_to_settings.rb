class AddCountryCodeListToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :country_code_list, :string
    add_column :settings, :phone_numbers, :string
  end
end
