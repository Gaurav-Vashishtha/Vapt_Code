class AddPostSendOnlyWhatsappToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :post_send_only_whatsapp, :boolean, default:false
  end
end
