# frozen_string_literal: true

# Support dashboard → WhatsApp languages.
#   1. Translate COD King's default-number MSG91 templates (AI draft, human review, submit to Meta),
#      and follow their review status.
#   2. Choose the WhatsApp language suggested during onboarding for each shop country (English when
#      a country has none, or its language is not approved yet).
class WhatsappTemplateTranslationsDashboardController < ApplicationController
  before_action :authenticate_admin!
  before_action :load_translation, only: %i[edit update draft submit]

  def index
    @languages = WhatsappTemplateTranslation::LANGUAGES
    @in_use = Whatsapp::DefaultTemplates.in_use_names
    rows = WhatsappTemplateTranslation.order(:template_name, :language).to_a
    @rows_by_template = rows.group_by(&:template_name)
    @template_names = (@in_use + @rows_by_template.keys).uniq.sort
    @counts = rows.group_by(&:language).transform_values { |list| list.group_by(&:status).transform_values(&:size) }
    @country_languages = WhatsappCountryLanguage.order(:country_code).to_a
    @ai_ready = ENV.fetch("ANTHROPIC_API_KEY", nil).present?
    @msg91_ready = ENV.fetch("MSG91_AUTHKEY", nil).present? && ENV.fetch("WHATSAPP_NUMBER_DEFAULT", nil).present?
  end

  def refresh
    result = Whatsapp::TemplateTranslationSync.new.refresh_sources!
    notice = "Fetched #{result.sources_found}/#{result.in_use.size} templates in use from MSG91 " \
             "(#{result.rows_created} new rows, #{result.changes.size} status changes)."
    notice += " No approved English version on MSG91 for: #{result.missing_sources.join(', ')}." if result.missing_sources.any?
    redirect_to support_dashboard_whatsapp_languages_path, notice: notice
  rescue Msg91::WhatsappTemplateClient::Error => e
    redirect_to support_dashboard_whatsapp_languages_path, alert: "#{e.message} #{e.response.to_json.first(300)}"
  end

  def sync_statuses
    result = Whatsapp::TemplateTranslationSync.new.sync_statuses!
    redirect_to support_dashboard_whatsapp_languages_path, notice: "Review status refreshed (#{result.changes.size} changes)."
  rescue Msg91::WhatsappTemplateClient::Error => e
    redirect_to support_dashboard_whatsapp_languages_path, alert: "#{e.message} #{e.response.to_json.first(300)}"
  end

  # Queue AI drafts for every not-started row of a language.
  def draft_all
    language = params[:language].to_s
    return redirect_to(support_dashboard_whatsapp_languages_path, alert: "Unknown language") unless WhatsappTemplateTranslation::LANGUAGES.key?(language)

    ids = WhatsappTemplateTranslation.where(language: language, status: "not_started")
                                     .where.not(source_components: []).pluck(:id)
    Whatsapp::TemplateTranslationDraftJob.perform_async(ids) if ids.any?
    redirect_to support_dashboard_whatsapp_languages_path,
                notice: ids.any? ? "Drafting #{ids.size} #{WhatsappTemplateTranslation.language_name(language)} translations — refresh in a minute." : "Nothing to draft."
  end

  # Review every draft of one language on a single page before submitting them together.
  def bulk_review
    @language = params[:language].to_s
    return redirect_to(support_dashboard_whatsapp_languages_path, alert: "Unknown language") unless WhatsappTemplateTranslation::LANGUAGES.key?(@language)

    @drafts = WhatsappTemplateTranslation.where(language: @language, status: "draft").order(:template_name).map do |row|
      problems = if row.category.to_s.casecmp?("AUTHENTICATION")
                   [] # submitted with Meta's own wording; the drafted text isn't sent
                 else
                   Whatsapp::TemplateTranslationValidator.errors(row.source_components, row.components)
                 end
      { row: row, errors: problems }
    end
  end

  def bulk_submit
    language = params[:language].to_s
    reviewer = params[:reviewer].to_s.strip
    ids = Array(params[:ids]).map(&:to_i).uniq
    back = support_dashboard_whatsapp_languages_bulk_review_path(language: language)
    return redirect_to(back, alert: "Enter your name to confirm you reviewed these translations.") if reviewer.empty?
    return redirect_to(back, alert: "Select at least one translation.") if ids.empty?

    ids = WhatsappTemplateTranslation.where(id: ids, language: language, status: "draft").pluck(:id)
    Whatsapp::TemplateTranslationBulkSubmitJob.perform_async(ids, reviewer) if ids.any?
    redirect_to support_dashboard_whatsapp_languages_path,
                notice: "Submitting #{ids.size} #{WhatsappTemplateTranslation.language_name(language)} translations for Meta review — refresh in a minute. Results are also posted to Slack."
  end

  def edit
    @strings = Whatsapp::TemplateComponents.translatable(@translation.source_components)
    current = Whatsapp::TemplateComponents.translatable(@translation.components).to_h { |s| [s["id"], s["text"]] }
    @current_text = @strings.to_h { |s| [s["id"], current[s["id"]].to_s] }
    @errors = if @translation.category.to_s.casecmp?("AUTHENTICATION") || @translation.components.blank?
                [] # Authentication templates submit with Meta's own wording, not the drafted text
              else
                Whatsapp::TemplateTranslationValidator.errors(@translation.source_components, @translation.components)
              end
  end

  def update
    return redirect_to(edit_path, alert: "This translation is #{@translation.status} and can't be edited.") unless @translation.editable?

    texts = params.fetch(:texts, {}).permit!.to_h
    list = texts.map { |id, text| { "id" => id.to_s, "text" => text.to_s.strip } }
    components = Whatsapp::TemplateComponents.apply(@translation.source_components, list)
    @translation.update!(components: components, status: "draft", drafted_by: @translation.drafted_by.presence || "manual",
                         rejection_reason: @translation.status == "rejected" ? @translation.rejection_reason : nil)
    redirect_to edit_path, notice: "Saved."
  end

  def draft
    return redirect_to(edit_path, alert: "This translation is #{@translation.status} and can't be redrafted.") unless @translation.editable?

    components = Whatsapp::TemplateTranslator.new.translate(@translation.source_components, @translation.language)
    @translation.update!(components: components, status: "draft", drafted_by: "ai")
    redirect_to edit_path, notice: "AI draft ready — review every line before submitting."
  rescue Whatsapp::TemplateTranslator::Error => e
    redirect_to edit_path, alert: e.message
  end

  def submit
    reviewer = params[:reviewer].to_s.strip
    return redirect_to(edit_path, alert: "Enter your name to confirm you reviewed this translation.") if reviewer.empty?

    result = Whatsapp::TemplateTranslationSubmitter.new.call(@translation, submitted_by: reviewer)
    if result.ok
      redirect_to support_dashboard_whatsapp_languages_path,
                  notice: "Submitted #{@translation.template_name} (#{WhatsappTemplateTranslation.language_name(@translation.language)}) for Meta review."
    else
      redirect_to edit_path, alert: result.errors.join(" ")
    end
  end

  def save_country_language
    record = WhatsappCountryLanguage.find_or_initialize_by(country_code: params[:country_code].to_s.strip.upcase)
    record.language = params[:language].to_s
    if record.save
      redirect_to support_dashboard_whatsapp_languages_path(anchor: "countries"), notice: "#{record.country_code} → #{WhatsappTemplateTranslation.language_name(record.language)} saved."
    else
      redirect_to support_dashboard_whatsapp_languages_path(anchor: "countries"), alert: record.errors.full_messages.join(", ")
    end
  end

  def destroy_country_language
    record = WhatsappCountryLanguage.find(params[:id])
    record.destroy!
    redirect_to support_dashboard_whatsapp_languages_path(anchor: "countries"), notice: "#{record.country_code} now falls back to English."
  end

  private

  def load_translation
    @translation = WhatsappTemplateTranslation.find(params[:id])
  end

  def edit_path
    edit_support_dashboard_whatsapp_language_path(@translation)
  end

  def authenticate_admin!
    http_basic_authenticate_or_request_with(name: ENV.fetch("ADMIN_USER", nil), password: ENV.fetch("ADMIN_PASS", nil))
  end
end
