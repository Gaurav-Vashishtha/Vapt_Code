# frozen_string_literal: true

module Api
  module Form
    # GET /api/form/config — what the storefront needs to draw the form's fields before the
    # session exists: the published form, the country list and the address rules of the buyer's
    # country. No Shopify call and no prices, so it answers at once; POST /api/form/session
    # still decides everything (form targeting, eligibility, totals) and replaces this.
    # No token, origin-checked, briefly cacheable (the config version is part of the URL).
    class ConfigsController < BaseController
      CACHE_CONTROL = "public, max-age=60"
      RTL_LANGUAGES = %w[ar ur he fa].freeze

      skip_before_action :parse_body!
      skip_before_action :check_module!
      skip_before_action :authenticate_session!

      def show
        response.headers["Cache-Control"] = CACHE_CONTROL
        render json: payload || { "form" => nil }
      end

      private

      # nil whenever the early form could differ from what the session will answer.
      def payload
        availability = CodForm::Availability.call(shop, config: shop_config)
        return nil unless CodForm::Availability.usable?(availability, test: false)

        general = CodForm::QuoteService.general_settings(shop_config)
        country = country_for(general)
        return nil if country.nil?

        # With several active forms the session picks one by its targeting: wait for it.
        forms = CodForm::Form.where(shop_id: shop.id).active.ordered.limit(2).to_a
        return nil if forms.size > 1

        form = forms.first || CodForm::Form.default_for(shop)
        return nil unless form.published_config.is_a?(Hash) && form.published_config.any?

        locale = CodForm::Engine::FormConfig.storefront_locale(form.published_config, clean_locale(params[:locale]), general["language"])
        {
          "config_version" => shop_config.config_version,
          "locale" => locale,
          "rtl" => RTL_LANGUAGES.include?(locale.split("-").first),
          "form" => {
            "id" => form.id, "version" => form.published_version,
            "config" => CodForm::Engine::FormConfig.for_storefront(form.published_config, locale: locale)
          },
          "countries" => CodForm::CatalogService.countries_for(general, country),
          "country_schema" => CodForm::CatalogService.country_schema(country)
        }
      end

      def country_for(general)
        country = params[:country].to_s.strip.upcase
        country = shop.country_code.to_s.strip.upcase unless country.match?(/\A[A-Z]{2}\z/)
        enabled = Array(general["countries"]).map { |c| c.to_s.upcase }
        return nil unless country.match?(/\A[A-Z]{2}\z/)
        return nil unless enabled.empty? || enabled.include?(country)

        country
      end

      def clean_locale(value)
        locale = value.to_s.strip.tr("_", "-")
        locale.match?(/\A[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?\z/) ? locale.downcase[0, 12] : "en"
      end
    end
  end
end
