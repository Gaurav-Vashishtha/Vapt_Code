# frozen_string_literal: true

class AddLastErrorToWhatsappCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :whatsapp_campaigns, :last_error, :text
  end
end
