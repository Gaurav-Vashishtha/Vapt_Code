class CreateProvinces < ActiveRecord::Migration[6.0]
  def change
    create_table :provinces do |t|
      t.string :country_name
      t.string :country_code
      t.string :country_id
      t.string :province_name
      t.string :province_code
      t.string :province_id
      t.string :description
      t.timestamps
    end
  end
end
