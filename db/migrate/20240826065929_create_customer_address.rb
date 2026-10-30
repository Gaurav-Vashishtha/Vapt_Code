class CreateCustomerAddress < ActiveRecord::Migration[6.0]
  def change
    create_table :customer_addresses do |t|
    t.string :first_name
    t.string :last_name
    t.string :company
    t.string :address1
    t.string :address2
    t.string :city
    t.string :province
    t.string :country
    t.string :zip
    t.string :phone
    t.string :province_code
    t.string :country_code
    t.string :country_name
    t.string :formatted
    t.string :formatted_area
    t.string :latitude
    t.string :longitude
    t.string :coordinates_validated
    t.string :country_code_v2
    t.string :shopify_id
    t.boolean :default
    t.timestamps
    t.references :customer, foreign_key: true
    end
  end
end
