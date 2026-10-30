# frozen_string_literal: true

class AddFreeGiftConfigToAdditionalSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :additional_settings, :free_gift_config, :jsonb, if_not_exists: true
  end
end
