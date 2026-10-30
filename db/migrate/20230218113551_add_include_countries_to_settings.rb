class AddIncludeCountriesToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :include_countries, :string
  end
end
