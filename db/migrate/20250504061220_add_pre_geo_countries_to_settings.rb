class AddPreGeoCountriesToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :pre_geo_countries, :string, default:''
  end
end
