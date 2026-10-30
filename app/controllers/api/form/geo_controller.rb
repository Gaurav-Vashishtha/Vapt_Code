# frozen_string_literal: true

module Api
  module Form
    # GET /api/form/geo/:country and /api/form/geo/:country/postal/:code (D.11).
    # No token, origin-checked, throttled with the quote bucket. Static data: cached for a day.
    class GeoController < BaseController
      CACHE_CONTROL = "public, max-age=86400"

      skip_before_action :parse_body!
      skip_before_action :check_module!
      skip_before_action :authenticate_session!

      def show
        country = params[:country].to_s.upcase
        dataset = CodForm::CatalogService.geo_dataset(country)
        provinces = CodForm::CatalogService.provinces(country)
        cities = dataset && dataset["cities"].is_a?(Hash) ? dataset["cities"] : free_cities

        response.headers["Cache-Control"] = CACHE_CONTROL
        render json: {
          "country" => country,
          # Same resolved schema as the session response: province mode is "select" only when
          # `provinces` below is not empty, otherwise "hidden".
          "schema" => CodForm::Engine::CountrySchema.resolve(
            CodForm::Engine::CountrySchema.for(country: country), has_provinces: provinces.any?
          ),
          "provinces" => provinces,
          "cities" => cities
        }
      end

      # India pincode lookup (FRM-6) from the existing `locations` table.
      def postal
        country = params[:country].to_s.upcase
        code = params[:code].to_s.strip
        location = Location.where(zipcode: code, country: country).first

        response.headers["Cache-Control"] = CACHE_CONTROL
        if location.nil?
          render json: { "found" => false }
        else
          render json: { "found" => true, "city" => location.city.to_s, "province" => province_code(country, location.province.to_s) }
        end
      end

      private

      def free_cities
        { "mode" => "free", "list" => [], "by_province" => {} }
      end

      # `locations.province` holds a code or a name depending on the import: answer with the
      # code the province select uses whenever it can be resolved.
      def province_code(country, value)
        return value if value.empty?

        list = CodForm::CatalogService.provinces(country)
        match = list.find { |p| p["code"].to_s.casecmp?(value) } || list.find { |p| p["name"].to_s.casecmp?(value) }
        match ? match["code"] : value
      end
    end
  end
end
