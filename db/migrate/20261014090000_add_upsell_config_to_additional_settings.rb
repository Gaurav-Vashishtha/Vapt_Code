# frozen_string_literal: true

class AddUpsellConfigToAdditionalSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :additional_settings, :upsell_config, :jsonb
  end
end
