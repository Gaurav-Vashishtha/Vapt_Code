class AddAcWhatsappScheduleToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :ac_whatsapp_schedule, :string, default:'0'
    add_column :settings, :ac_sms_schedule, :string, default:'0'
  end
end
