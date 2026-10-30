class CreateTwilioPricing < ActiveRecord::Migration[6.0]
  def change
    create_table :twilio_pricings do |t|
      t.string :country_code
      t.string :country
      t.string :sms_price
    end
  end
end
