# frozen_string_literal: true

module Whatsapp
  # Language code to send a default-number MSG91 template in.
  #
  # The shop's chosen language is used only when that template is approved in it; otherwise the
  # message goes out in English, so a half-translated language never drops a message. Languages this
  # system does not manage (en, or legacy codes such as "it" set for custom templates) and shops that
  # send from their own WhatsApp number pass through unchanged.
  module TemplateLanguage
    module_function

    CACHE_KEY = "whatsapp/template_language/approved/v1"
    CACHE_TTL = 10.minutes
    FALLBACK = WhatsappTemplateTranslation::SOURCE_LANGUAGE

    def for(shop, template_name, requested: nil)
      setting = shop&.setting
      language = (requested.presence || setting&.whatsapp_language_code.presence || FALLBACK).to_s
      return language unless managed?(language)
      return language if setting && !DefaultTemplates.default_number?(setting)

      approved?(template_name, language) ? language : FALLBACK
    rescue StandardError => e
      Rails.logger.error("[Whatsapp::TemplateLanguage] #{e.class}: #{e.message} shop=#{shop&.id} template=#{template_name}")
      FALLBACK
    end

    def managed?(language)
      WhatsappTemplateTranslation::LANGUAGES.key?(language.to_s)
    end

    def approved?(template_name, language)
      approved_keys.include?(key(template_name, language))
    end

    def approved_keys
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
        WhatsappTemplateTranslation.approved.pluck(:template_name, :language).map { |name, lang| key(name, lang) }
      end.to_set
    end

    def clear_cache!
      Rails.cache.delete(CACHE_KEY)
    end

    def key(template_name, language)
      "#{template_name}|#{language}"
    end

    # Template names behind the shop's previewable notifications (what "fully approved" is judged on).
    def preview_template_names(shop)
      setting = shop&.setting
      return [] unless setting

      DefaultTemplates::PREVIEW_EVENTS.flat_map { |event| DefaultTemplates.names_for(setting, event) }.uniq
    end

    # Languages offered to the shop: English plus each managed language with its approval coverage.
    def options_for(shop)
      names = preview_template_names(shop)
      english = { code: FALLBACK, name: "English", native: "English", rtl: false,
                  approved_count: names.size, total_count: names.size, fully_approved: true }

      managed = WhatsappTemplateTranslation::LANGUAGES.map do |code, meta|
        approved = names.count { |name| approved?(name, code) }
        { code: code, name: meta[:name], native: meta[:native], rtl: meta[:rtl] == true,
          approved_count: approved, total_count: names.size, fully_approved: names.any? && approved == names.size }
      end

      [english, *managed.select { |opt| opt[:approved_count].positive? }]
    end

    # Onboarding default: the country's language when every previewed template is approved in it,
    # otherwise English.
    def suggested_for(shop)
      language = WhatsappCountryLanguage.language_for(shop&.country_code)
      return FALLBACK unless language && managed?(language)

      names = preview_template_names(shop)
      names.any? && names.all? { |name| approved?(name, language) } ? language : FALLBACK
    end
  end
end
