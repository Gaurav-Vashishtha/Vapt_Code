class AddWhatsappApprovalStatusAndNotesToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :whatsapp_approval_status, :string, default: "send_request", null: false
    add_column :settings, :whatsapp_approval_notes, :string
  end
end
