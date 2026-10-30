class CreateSmsProviderCountryMappings < ActiveRecord::Migration[7.2]
  def change
    create_table :sms_provider_country_mappings do |t|
      t.string :provider, null: false
      t.text :supported_countries, null: false

      t.timestamps
    end
    
    add_index :sms_provider_country_mappings, :provider, unique: true
  end
end
