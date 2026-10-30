# frozen_string_literal: true

class AddRecipeKeyToWhatsappCampaigns < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      add_column :whatsapp_campaigns, :recipe_key, :string
    end
  end
end
