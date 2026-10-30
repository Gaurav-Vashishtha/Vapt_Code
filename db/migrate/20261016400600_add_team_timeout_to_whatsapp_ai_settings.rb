# frozen_string_literal: true

class AddTeamTimeoutToWhatsappAiSettings < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      add_column :whatsapp_ai_settings, :team_timeout_minutes, :integer, null: false, default: 30
    end
  end
end
