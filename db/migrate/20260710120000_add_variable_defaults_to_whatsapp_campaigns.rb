# frozen_string_literal: true

class AddVariableDefaultsToWhatsappCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :whatsapp_campaigns, :variable_defaults, :jsonb, default: {}
    add_column :whatsapp_campaigns, :missing_value_policy, :string, default: "default", null: false
  end
end
