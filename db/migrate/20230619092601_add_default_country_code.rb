class AddDefaultCountryCode < ActiveRecord::Migration[6.0]
  def change
    change_column_default :settings, :country_code_list , from: nil, to: ''
  end
end
