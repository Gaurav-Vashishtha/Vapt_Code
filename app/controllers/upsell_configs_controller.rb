# frozen_string_literal: true

class UpsellConfigsController < AuthenticatedController
  # GET /upsell_config
  def show
    render json: payload(Upsells::Config.sanitize(@shop.additional_setting&.upsell_config))
  end

  # POST /upsell_config
  def create
    config = Upsells::Config.sanitize(params.require(:upsell_config).to_unsafe_h)
    record = @shop.additional_setting || @shop.build_additional_setting
    if record.update(upsell_config: config)
      render json: payload(config)
    else
      render json: { error: record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def payload(config)
    items = config ? config["items"] : []
    catalog = Upsells::Catalog.nodes(
      @shop,
      products: items.select { |i| i["type"] == "product" }.map { |i| i["shopify_id"] },
      collections: items.select { |i| i["type"] == "collection" }.map { |i| i["shopify_id"] }
    )
    { config: config, products: catalog[:products].values, collections: catalog[:collections].values }
  rescue StandardError => e
    Rails.logger.warn("[UpsellConfigs] shop_id=#{@shop.id} #{e.class}: #{e.message.to_s[0, 200]}")
    { config: config, products: [], collections: [] }
  end
end
