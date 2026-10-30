# frozen_string_literal: true

# Egypt campaign: approve WhatsApp (default number) requests already waiting from Egyptian stores.
# New requests are approved on the spot by Whatsapp::AutoApprovalPolicy. Rejected and untouched
# (send_request) shops are left alone. No approval email is sent from here.
class AutoApproveEgyptWhatsappRequests < ActiveRecord::Migration[7.2]
  class MigrationSetting < ActiveRecord::Base
    self.table_name = "settings"
  end

  def up
    shop_ids = select_values("SELECT id FROM shops WHERE UPPER(country_code) = 'EG'")
    return if shop_ids.empty?

    changes = { whatsapp_approval_status: "approved",
                whatsapp_approval_notes: "Auto-approved: EG store (fast-track country, backfill)" }
    # settings has no timestamps in some environments; only touch updated_at when it exists.
    changes[:updated_at] = Time.current if column_exists?(:settings, :updated_at)

    count = MigrationSetting.where(shop_id: shop_ids, whatsapp_approval_status: "requested").update_all(changes)
    say "Approved #{count} pending Egyptian WhatsApp requests"
  end

  def down
    # Approvals are not reverted automatically.
  end
end
