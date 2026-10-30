require 'csv'

module Whatsapp
  # Parses an uploaded CSV: detects headers, guesses the phone column, counts
  # valid phone rows, and marks the import ready for mapping.
  class ImportCsvAudienceJob < ApplicationJob
    sidekiq_options queue: 'whatsapp_bsp_campaign', retry: 1

    def perform(import_id)
      import = WhatsappAudienceImport.find_by(id: import_id)
      return unless import
      content = import.raw_content.presence || (import.file.attached? ? import.file.download : nil)
      return if content.blank?
      import.update_columns(status: 'parsing', updated_at: Time.current)

      table = CSV.parse(content, headers: true)
      headers = Array(table.headers).compact
      phone_col = import.phone_column.presence || guess_phone_column(headers)
      name_col  = import.name_column.presence  || guess_column(headers, /\bname\b|full.?name|first.?name|customer/)
      email_col = import.email_column.presence || guess_column(headers, /e.?mail/)

      valid = 0
      table.each { |row| valid += 1 if phone_col && row[phone_col].to_s.strip.present? }

      import.update!(status: 'ready', columns: headers, row_count: table.size,
                     valid_count: valid, phone_column: phone_col,
                     name_column: name_col, email_column: email_col)
    rescue => e
      Rails.logger.error("[Whatsapp::ImportCsvAudienceJob] import=#{import_id} #{e.class}: #{e.message}")
      WhatsappAudienceImport.where(id: import_id).update_all(status: 'failed', error: e.message, updated_at: Time.current)
    end

    private

    def guess_phone_column(headers)
      headers.find { |h| h.to_s.downcase.match?(/phone|mobile|whatsapp|number|msisdn|contact/) }
    end

    def guess_column(headers, pattern)
      headers.find { |h| h.to_s.downcase.match?(pattern) }
    end
  end
end
