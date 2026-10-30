class AddWhatsappOperatorToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :whatsapp_operator_config, :string, default:''
  end
end
