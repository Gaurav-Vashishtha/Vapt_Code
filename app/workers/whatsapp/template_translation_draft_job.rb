# frozen_string_literal: true

module Whatsapp
  # Drafts AI translations for the given WhatsappTemplateTranslation ids (support dashboard
  # "Draft all"). Rows that were edited or submitted meanwhile are skipped.
  class TemplateTranslationDraftJob < ApplicationJob
    sidekiq_options queue: "default", retry: false

    def perform(ids)
      translator = Whatsapp::TemplateTranslator.new
      WhatsappTemplateTranslation.where(id: Array(ids), status: "not_started").find_each do |row|
        components = translator.translate(row.source_components, row.language)
        row.update!(components: components, status: "draft", drafted_by: "ai")
      rescue Whatsapp::TemplateTranslator::Error => e
        row.update!(status: "failed", rejection_reason: "AI draft failed: #{e.message}")
      end
    end
  end
end
