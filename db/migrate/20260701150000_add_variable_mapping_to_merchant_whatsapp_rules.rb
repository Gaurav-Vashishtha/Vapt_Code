# frozen_string_literal: true

class AddVariableMappingToMerchantWhatsappRules < ActiveRecord::Migration[7.2]
  def change
    add_column :merchant_whatsapp_rules, :variable_mapping, :jsonb, default: {}
  end
end
