class AddAcWhatsappToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :ac_whatsapp, :boolean, default: false
  end
end
