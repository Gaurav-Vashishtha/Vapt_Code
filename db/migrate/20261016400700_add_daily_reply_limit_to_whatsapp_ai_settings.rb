# frozen_string_literal: true

class AddDailyReplyLimitToWhatsappAiSettings < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      add_column :whatsapp_ai_settings, :daily_reply_limit, :integer, null: false, default: 40
    end
  end
end
