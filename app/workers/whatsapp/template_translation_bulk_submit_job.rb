# frozen_string_literal: true

module Whatsapp
  # Submits several reviewed translations to MSG91 one by one (support dashboard "Submit all drafts").
  # Each row goes through the same checks as a single submit; failures are kept on the row and the
  # outcome is posted to Slack.
  class TemplateTranslationBulkSubmitJob < ApplicationJob
    sidekiq_options queue: "default", retry: false

    def perform(ids, reviewer)
      submitter = Whatsapp::TemplateTranslationSubmitter.new
      submitted = []
      failed = []

      WhatsappTemplateTranslation.where(id: Array(ids), status: "draft").order(:template_name).each do |row|
        result = submitter.call(row, submitted_by: reviewer)
        label = "`#{row.template_name}` (#{WhatsappTemplateTranslation.language_name(row.language)})"
        result.ok ? submitted << label : failed << "#{label}: #{result.errors.join(' ').first(200)}"
      end

      notify(submitted, failed, reviewer)
    end

    private

    def notify(submitted, failed, reviewer)
      return if submitted.empty? && failed.empty?

      lines = [":globe_with_meridians: WhatsApp translations bulk submit by #{reviewer} (#{Rails.env})"]
      lines << "Submitted for Meta review (#{submitted.size}): #{submitted.join(', ')}" if submitted.any?
      lines << "Failed (#{failed.size}):\n#{failed.map { |f| "• #{f}" }.join("\n")}" if failed.any?
      SlackNotifier::CLIENT.ping(text: lines.join("\n"))
    rescue StandardError => e
      Rails.logger.warn("[TemplateTranslationBulkSubmitJob] Slack notify failed: #{e.message}")
    end
  end
end
