# frozen_string_literal: true

class FreeGiftConfigsController < AuthenticatedController
  # GET /free_gift_config
  def show
    render json: payload(FreeGifts.config_for(@shop))
  end

  # POST /free_gift_config
  def create
    config = FreeGifts::Config.sanitize(params.require(:free_gift_config).to_unsafe_h)
    errors = FreeGifts::Config.errors(config)
    return render json: { error: errors.to_sentence, errors: errors }, status: :unprocessable_entity if errors.any?

    config["rules"] = FreeGifts::Catalog.hydrate_rules(@shop, config["rules"])
    record = @shop.additional_setting || @shop.build_additional_setting
    if record.update(free_gift_config: config)
      render json: payload(config)
    else
      render json: { error: record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def payload(config)
    rules = config["rules"]
    catalog = Upsells::Catalog.nodes(
      @shop,
      products: rules.flat_map { |rule| rule["product_ids"] },
      collections: rules.flat_map { |rule| rule["collection_ids"] }
    )
    gifts = FreeGifts::Catalog.variants(@shop, rules.map { |rule| rule["gift_variant_id"] })
    {
      config: config,
      products: catalog[:products].values.map { |p| p.slice("id", "title", "image") },
      collections: catalog[:collections].values.map { |c| c.slice("id", "title", "image", "products_count") },
      gift_status: gifts.transform_values { |g| { available: g[:available], active: g[:product_status] == "ACTIVE" } }
    }
  rescue StandardError => e
    Rails.logger.warn("[FreeGiftConfigs] shop_id=#{@shop.id} #{e.class}: #{e.message.to_s[0, 200]}")
    { config: config, products: [], collections: [], gift_status: {} }
  end
end
