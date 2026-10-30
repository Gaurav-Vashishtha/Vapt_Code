# frozen_string_literal: true

module Whatsapp
  # Keeps WhatsappTemplateTranslation in step with MSG91.
  #
  # refresh_sources! — pull the English version of every template in use and make sure each managed
  #   language has a row for it (a translation already present on MSG91 is picked up as-is).
  # sync_statuses!   — refresh every row's status from the version MSG91 has (if any).
  class TemplateTranslationSync
    MSG91_STATUS = {
      "approved" => "approved",
      "pending" => "pending",
      "in_appeal" => "pending",
      "submitted" => "pending",
      "rejected" => "rejected",
      "paused" => "rejected",
      "disabled" => "rejected"
    }.freeze

    Result = Struct.new(:in_use, :sources_found, :missing_sources, :rows_created, :changes, keyword_init: true)

    def initialize(client: Msg91::WhatsappTemplateClient.new)
      @client = client
    end

    def refresh_sources!
      remote = @client.templates.group_by { |t| t[:name] }
      names = DefaultTemplates.in_use_names
      missing = []
      created = 0
      changes = []

      names.each do |name|
        versions = Array(remote[name])
        source = english_version(versions)
        unless source
          missing << name
          next
        end

        WhatsappTemplateTranslation::LANGUAGES.each_key do |language|
          row = WhatsappTemplateTranslation.find_or_initialize_by(template_name: name, language: language)
          created += 1 if row.new_record?
          row.source_components = source[:components]
          row.category = source[:category] if source[:category]
          if (existing = version_in(versions, language))
            apply_remote(row, existing, changes)
          end
          row.last_synced_at = Time.current
          row.save!
        end
      end

      notify(changes)
      Result.new(in_use: names, sources_found: names.size - missing.size, missing_sources: missing,
                 rows_created: created, changes: changes)
    end

    def sync_statuses!
      # Every row, whatever its local status: MSG91 is shared by all environments (local, staging,
      # prod), so a version submitted from one shows up as failed/draft in another's database until
      # it is reconciled here. Rows with no version on MSG91 are left as they are.
      rows = WhatsappTemplateTranslation.all.to_a
      return Result.new(in_use: [], sources_found: 0, missing_sources: [], rows_created: 0, changes: []) if rows.empty?

      remote = @client.templates.group_by { |t| t[:name] }
      changes = []
      rows.each do |row|
        existing = version_in(Array(remote[row.template_name]), row.language)
        next unless existing

        apply_remote(row, existing, changes)
        row.last_synced_at = Time.current
        row.save!
      end

      notify(changes)
      Result.new(in_use: [], sources_found: 0, missing_sources: [], rows_created: 0, changes: changes)
    end

    private

    def english_version(versions)
      approved = versions.select { |v| v[:status] == "approved" }
      approved.find { |v| v[:language] == "en" } || approved.find { |v| v[:language].start_with?("en") }
    end

    def version_in(versions, language)
      versions.find { |v| v[:language] == language } ||
        versions.find { |v| v[:language].split("_").first == language }
    end

    def apply_remote(row, remote, changes)
      status = MSG91_STATUS[remote[:status].to_s] || row.status
      before = row.status
      row.status = status
      row.components = remote[:components] if row.components.blank? && remote[:components].present?
      row.rejection_reason = status == "rejected" ? (remote[:rejection_reason] || "#{remote[:status]} on Meta") : nil
      row.approved_at ||= Time.current if status == "approved"
      row.approved_at = nil unless status == "approved"
      changes << { name: row.template_name, language: row.language, from: before, to: status } if before != status
    end

    def notify(changes)
      return if changes.empty?

      lines = changes.map do |c|
        "• `#{c[:name]}` (#{WhatsappTemplateTranslation.language_name(c[:language])}): #{c[:from]} → *#{c[:to]}*"
      end
      SlackNotifier::CLIENT.ping(text: ":globe_with_meridians: WhatsApp template translations (#{Rails.env})\n#{lines.join("\n")}")
    rescue StandardError => e
      Rails.logger.warn("[TemplateTranslationSync] Slack notify failed: #{e.message}")
    end
  end
end
