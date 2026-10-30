# frozen_string_literal: true

class AddSendGuardrails < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  IN_FLIGHT = %w[building scheduled sending paused retry_waiting].freeze

  def up
    with_lock_retries do
      add_column :whatsapp_campaigns, :send_policy, :jsonb, default: {}, null: false
      add_column :whatsapp_campaigns, :pause_reason, :string
      add_column :whatsapp_campaigns, :pause_detail, :jsonb, default: {}, null: false
      add_column :whatsapp_campaigns, :paused_at, :datetime
      add_column :whatsapp_campaigns, :guardrail_notified_at, :datetime

      add_column :whatsapp_accounts, :messaging_limit_tier, :string
      add_column :whatsapp_accounts, :quality_updated_at, :datetime
      add_column :whatsapp_accounts, :previous_quality_rating, :string

      # Campaigns already going out keep today's behaviour; only new ones get the
      # quiet-hours and frequency-cap defaults (PM decision D10).
      execute <<~SQL.squish
        UPDATE whatsapp_campaigns
        SET send_policy = '{"quiet_hours":{"enabled":false},"frequency_cap":{"enabled":false}}'::jsonb
        WHERE status IN (#{IN_FLIGHT.map { |s| connection.quote(s) }.join(', ')})
      SQL
    end
  end

  def down
    remove_column :whatsapp_campaigns, :send_policy
    remove_column :whatsapp_campaigns, :pause_reason
    remove_column :whatsapp_campaigns, :pause_detail
    remove_column :whatsapp_campaigns, :paused_at
    remove_column :whatsapp_campaigns, :guardrail_notified_at

    remove_column :whatsapp_accounts, :messaging_limit_tier
    remove_column :whatsapp_accounts, :quality_updated_at
    remove_column :whatsapp_accounts, :previous_quality_rating
  end
end
