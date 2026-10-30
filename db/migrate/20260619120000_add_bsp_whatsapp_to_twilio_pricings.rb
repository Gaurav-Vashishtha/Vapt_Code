class AddBspWhatsappToTwilioPricings < ActiveRecord::Migration[7.2]
  # BSP (Meta Cloud API) WhatsApp has its own per-country base price that's
  # cheaper than the legacy MSG91 path. We bill it separately so we can keep
  # MSG91 pricing intact while rolling BSP out across countries at different
  # rates.
  #
  # 0.003 USD/message is the default seed — that's roughly Meta's UTILITY
  # category list price after a typical BSP volume discount. Per-country
  # overrides can be set via the admin TwilioPricings dashboard once we have
  # specific deals.
  def change
    add_column :twilio_pricings, :bsp_whatsapp, :decimal, precision: 10, scale: 4,
               default: 0.003, null: false
  end
end
