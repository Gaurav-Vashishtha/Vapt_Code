class AddWhatsappToTwilioPricing < ActiveRecord::Migration[6.0]
  def change
    add_column :twilio_pricings, :whatsapp, :string
  end
end
