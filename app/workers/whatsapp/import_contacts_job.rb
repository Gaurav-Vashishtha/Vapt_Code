require 'csv'

module Whatsapp
  # Loads a parsed CSV import into the contact book. Mapped name/email columns
  # fill the contact fields; every other column becomes a custom attribute so
  # it stays usable as a campaign variable (contact.attr.<column>).
  class ImportContactsJob < ApplicationJob
    sidekiq_options queue: 'whatsapp_bsp_campaign', retry: 1
    BATCH = 500

    def perform(import_id, tags = [])
      import = WhatsappAudienceImport.find_by(id: import_id)
      return unless import
      content = import.raw_content.presence || (import.file.attached? ? import.file.download : nil)
      return if content.blank?

      tags = WhatsappContact.sanitize_tags(tags)
      now = Time.current
      table = CSV.parse(content, headers: true)
      headers = Array(table.headers).compact

      phone_col = import.phone_column.presence || headers.find { |h| h.to_s.downcase.match?(/phone|mobile|whatsapp|number|msisdn|contact/) }
      name_col  = import.name_column.presence  || headers.find { |h| h.to_s.downcase.match?(/\bname\b|full.?name|first.?name|customer/) }
      email_col = import.email_column.presence || headers.find { |h| h.to_s.downcase.match?(/e.?mail/) }
      if phone_col.blank?
        import.update_columns(status: 'failed', error: 'No phone number column found.', updated_at: Time.current)
        return
      end
      import.update_columns(status: 'parsing', columns: headers, row_count: table.size,
                            phone_column: phone_col, name_column: name_col, email_column: email_col,
                            updated_at: Time.current)
      mapped = [phone_col, name_col, email_col].compact

      rows = []
      imported = 0
      skipped = 0

      table.each do |row|
        phone = WhatsappContact.normalize_phone(phone_col ? row[phone_col] : nil)
        if phone.blank?
          skipped += 1
          next
        end

        attrs = row.to_h.except(*mapped).compact_blank.transform_keys { |k| k.to_s.strip }.transform_values(&:to_s)
        rows << { shop_id: import.shop_id, phone: phone, source: 'csv',
                  name: name_col ? row[name_col].to_s.strip.presence : nil,
                  email: email_col ? row[email_col].to_s.strip.presence : nil,
                  first_name: nil, last_name: nil,
                  tags: tags, attrs: attrs, order_count: 0, total_spent: 0,
                  source_ref: "import:#{import.id}", created_at: now, updated_at: now }
        if rows.size >= BATCH
          imported += WhatsappContact.merge_rows!(rows)
          rows.clear
        end
      end
      imported += WhatsappContact.merge_rows!(rows)

      import.update_columns(status: 'ready', valid_count: imported, updated_at: Time.current)
      Rails.logger.info("[Whatsapp::ImportContactsJob] import=#{import.id} imported=#{imported} skipped=#{skipped}")
    rescue => e
      Rails.logger.error("[Whatsapp::ImportContactsJob] import=#{import_id} #{e.class}: #{e.message}")
      WhatsappAudienceImport.where(id: import_id).update_all(status: 'failed', error: e.message, updated_at: Time.current)
    end
  end
end
