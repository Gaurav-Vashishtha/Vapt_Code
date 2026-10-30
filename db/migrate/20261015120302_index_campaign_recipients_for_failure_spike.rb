# frozen_string_literal: true

class IndexCampaignRecipientsForFailureSpike < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    # A killed CONCURRENTLY build leaves an INVALID index that if_not_exists would then skip forever.
    reversible { |dir| dir.up { execute("DROP INDEX CONCURRENTLY IF EXISTS idx_wa_campaign_recipients_campaign_last_attempt") if invalid_index?('idx_wa_campaign_recipients_campaign_last_attempt') } }

    add_index :whatsapp_campaign_recipients, %i[whatsapp_campaign_id last_attempt_at],
              where: 'last_attempt_at IS NOT NULL',
              algorithm: :concurrently,
              name: 'idx_wa_campaign_recipients_campaign_last_attempt',
              if_not_exists: true
  end
end
