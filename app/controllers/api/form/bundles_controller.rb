# frozen_string_literal: true

module Api
  module Form
    # GET /api/form/bundles?shop=…&product_id=…&country=…&locale=… — the bundles shown on a
    # product page (offer_type "bundle", "Show on the product page" on), with their products and
    # variants priced for the buyer's country. The embed loads the bundle widget only on the
    # pages of products that are in such a bundle (C.1 "bundles"). The bundle discount itself is
    # applied by the session / quote, from the cart, never from here.
    class BundlesController < BaseController
      CACHE_CONTROL = "public, max-age=60"

      skip_before_action :parse_body!
      skip_before_action :authenticate_session!

      def index
        response.headers["Cache-Control"] = CACHE_CONTROL
        render json: { "bundles" => bundles }
      end

      private

      def bundles
        product_id = params[:product_id].to_s
        return [] unless product_id.match?(/\A\d{1,20}\z/)
        return [] unless CodForm::Gates.flags(shop, config: shop_config)["quantity_offers"] == true

        offers = CodForm::Offer.where(shop_id: shop.id, offer_type: CodForm::Engine::Bundles::TYPE)
                               .active_now.ordered.map(&:to_engine_hash)
                               .select { |offer| offer.dig("config", "show_on_product_page") != false }
        offers = CodForm::Engine::Bundles.for_product(offers: offers, product_id: product_id).first(3)
        return [] if offers.empty?

        catalog = CodForm::CatalogService.variants(shop, CodForm::Engine::Bundles.variant_ids(offers), country: country)
        offers.filter_map { |offer| CodForm::Engine::Bundles.public_bundle(offer: offer, catalog: catalog) }
      rescue StandardError => e
        Rails.logger.warn("[Api::Form::Bundles] shop_id=#{shop&.id} #{e.class}")
        []
      end

      def country
        code = params[:country].to_s.strip.upcase
        code.match?(/\A[A-Z]{2}\z/) ? code : shop.country_code.to_s.upcase
      end
    end
  end
end
