class AddWhatsappUtilityAndMarketingToTwilioPricings < ActiveRecord::Migration[7.2]
  def change
    add_column :twilio_pricings, :whatsapp_utility, :decimal, precision: 10, scale: 4
    add_column :twilio_pricings, :whatsapp_marketing, :decimal, precision: 10, scale: 4
  end
end
