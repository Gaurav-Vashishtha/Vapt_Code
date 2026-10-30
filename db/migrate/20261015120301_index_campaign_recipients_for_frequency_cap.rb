# frozen_string_literal: true

class IndexCampaignRecipientsForFrequencyCap < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    # A killed CONCURRENTLY build leaves an INVALID index that if_not_exists would then skip forever.
    reversible { |dir| dir.up { execute("DROP INDEX CONCURRENTLY IF EXISTS idx_wa_campaign_recipients_shop_phone_sent") if invalid_index?('idx_wa_campaign_recipients_shop_phone_sent') } }

    add_index :whatsapp_campaign_recipients, %i[shop_id phone sent_at],
              where: 'sent_at IS NOT NULL',
              algorithm: :concurrently,
              name: 'idx_wa_campaign_recipients_shop_phone_sent',
              if_not_exists: true
  end
end
