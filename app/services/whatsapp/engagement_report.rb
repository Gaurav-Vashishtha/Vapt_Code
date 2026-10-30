# frozen_string_literal: true

module Whatsapp
  module EngagementReport
    EXCLUDED_EVENTS = %w[pre_order_otp].freeze
    SENT = WhatsappMessageLog.statuses.values_at('sent', 'delivered', 'read').freeze
    DELIVERED = WhatsappMessageLog.statuses.values_at('delivered', 'read').freeze
    READ = WhatsappMessageLog.statuses.fetch('read')
    FAILED = WhatsappMessageLog.statuses.fetch('failed')

    REPLIED_SQL = <<~SQL.squish
      EXISTS (
        SELECT 1 FROM whatsapp_inbound_messages im
        WHERE im.shop_id = whatsapp_message_logs.shop_id
          AND im.received_at >= COALESCE(whatsapp_message_logs.sent_at, whatsapp_message_logs.created_at)
          AND im.received_at < COALESCE(whatsapp_message_logs.sent_at, whatsapp_message_logs.created_at) + interval '24 hours'
          AND right(regexp_replace(im.from_phone, '\\D', '', 'g'), 10) =
              right(regexp_replace(whatsapp_message_logs.recipient, '\\D', '', 'g'), 10)
      )
    SQL

    module_function

    def call(shop, days)
      since = days.days.ago
      logs = WhatsappMessageLog.where(shop_id: shop.id)
                               .where('whatsapp_message_logs.created_at >= ?', since)
                               .where.not(event_type_key: EXCLUDED_EVENTS)

      counts = logs.group(:event_type_key).pluck(
        :event_type_key,
        Arel.sql("COUNT(*) FILTER (WHERE status IN (#{SENT.join(',')}))"),
        Arel.sql("COUNT(*) FILTER (WHERE status IN (#{DELIVERED.join(',')}))"),
        Arel.sql("COUNT(*) FILTER (WHERE status = #{READ})"),
        Arel.sql("COUNT(*) FILTER (WHERE status = #{FAILED})")
      )
      replied = logs.where(status: SENT).where(REPLIED_SQL).group(:event_type_key).count
      clicked = WhatsappLinkClick.where(shop_id: shop.id).where('clicked_at >= ?', since)
                                 .group(:event_type_key)
                                 .distinct
                                 .count(Arel.sql("COALESCE(source_external_id, '') || ':' || stage_index || ':' || COALESCE(recipient_last10, '')"))

      events = counts.map do |key, sent, delivered, read, failed|
        { event_type_key: key, sent: sent, delivered: delivered, read: read, failed: failed,
          clicked: clicked[key].to_i, replied: replied[key].to_i }
      end
      { days: days, events: events.sort_by { |e| -e[:sent] } }
    end
  end
end
