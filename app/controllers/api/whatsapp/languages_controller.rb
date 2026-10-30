# frozen_string_literal: true

module Api
  module Whatsapp
    # Merchant WhatsApp language for customer notifications (onboarding + notifications page):
    # the options the shop can pick, the onboarding suggestion for its country, and previews of each
    # notification in every offered language.
    #
    # PATCH saves the language (settings.whatsapp_language_code) and, unless it is the onboarding
    # suggestion being applied, records in additional_settings that the merchant chose it, so the
    # country default never overrides their pick.
    class LanguagesController < AuthenticatedController
      def index
        setting = @shop.setting
        own_number = setting.present? && !::Whatsapp::DefaultTemplates.default_number?(setting)
        options = ::Whatsapp::TemplateLanguage.options_for(@shop)

        render json: {
          current: setting&.whatsapp_language_code.presence || ::Whatsapp::TemplateLanguage::FALLBACK,
          selected_by_merchant: selected_by_merchant?,
          suggested: ::Whatsapp::TemplateLanguage.suggested_for(@shop),
          own_number: own_number,
          options: options,
          previews: own_number ? {} : previews(setting, options)
        }
      end

      def update
        setting = @shop.setting
        return render(json: { error: "Settings not found" }, status: :not_found) unless setting

        language = params[:language].to_s.strip
        allowed = ::Whatsapp::TemplateLanguage.options_for(@shop).map { |opt| opt[:code] }
        allowed << setting.whatsapp_language_code.to_s if setting.whatsapp_language_code.present?
        return render(json: { error: "Unsupported language" }, status: :unprocessable_entity) unless allowed.include?(language)

        suggested = ActiveModel::Type::Boolean.new.cast(params[:suggested])
        # The country default is applied only while the merchant hasn't chosen a language.
        if suggested && selected_by_merchant?
          return render(json: { language: setting.whatsapp_language_code, selected_by_merchant: true })
        end

        ActiveRecord::Base.transaction do
          setting.update!(whatsapp_language_code: language)
          unless suggested
            record = @shop.additional_setting || @shop.build_additional_setting
            record.update!(whatsapp_language_selected: true)
          end
        end

        render json: { language: language, selected_by_merchant: selected_by_merchant? }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      private

      def selected_by_merchant?
        record = @shop.reload_additional_setting
        record.respond_to?(:whatsapp_language_selected) && record.whatsapp_language_selected == true
      end

      # { "ur" => { "order_confirmation" => { template_name:, approved:, rtl:, components: } } }
      def previews(setting, options)
        return {} unless setting

        options.reject { |opt| opt[:code] == ::Whatsapp::TemplateLanguage::FALLBACK }.to_h do |opt|
          events = ::Whatsapp::DefaultTemplates::PREVIEW_EVENTS.to_h do |event|
            name = ::Whatsapp::DefaultTemplates.names_for(setting, event).first
            row = translations[[name, opt[:code]]]
            approved = row&.approved? == true
            [event, { template_name: name, approved: approved, rtl: opt[:rtl],
                      components: approved ? ::Whatsapp::TemplateComponents.normalize(row.components) : nil }]
          end
          [opt[:code], events]
        end
      end

      def translations
        @translations ||= WhatsappTemplateTranslation.approved.index_by { |t| [t.template_name, t.language] }
      end
    end
  end
end
