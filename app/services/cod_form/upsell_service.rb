# frozen_string_literal: true

module CodForm
  # One-click upsell after the order (ARCHITECTURE.md F.6, D.9, OFF-10).
  class UpsellService
    LOCK_SECONDS = 60

    class << self
      # => D.9 response body. Raises CodForm::Errors::ApiError (upsell_expired, out_of_stock, order_failed).
      def accept(session:, offer_id:, shop: nil)
        shop ||= Shop.find(session.shop_id)
        upsell = offered!(session, offer_id)
        offer = CodForm::Offer.where(shop_id: shop.id, offer_type: "upsell", id: upsell["offer_id"]).first
        raise CodForm::Errors.build("upsell_expired") if offer.nil? || !CodForm::Gates.allowed?(shop, "upsell")

        offer_config = offer.config.is_a?(Hash) ? offer.config : {}
        variant_id = offer_config["variant_id"].to_s
        quantity = [offer_config["quantity"].to_i, 1].max
        country = session.address.is_a?(Hash) ? session.address["country"] : session.country_code
        variant = CodForm::CatalogService.variants(shop, [variant_id], country: country)[variant_id]
        raise CodForm::Errors.build("out_of_stock", fields: { "items" => "error_out_of_stock" }) unless purchasable?(variant, quantity)

        # One accept at a time per session (double tap, two tabs).
        lock_key = "codf:upsell:#{session.id}"
        raise CodForm::Errors.build("already_processing") unless CodForm::Cache.store.write(lock_key, 1, unless_exist: true, expires_in: LOCK_SECONDS)

        begin
          unit_price = variant["unit_price_cents"].to_i
          discounted = discounted_unit_price(offer_config, unit_price, quantity)
          result = CodFormShopifyTimeout.with do
            ShopifyServices::OrderEditAddLineService.call(
              shop, order_id: session.order_id, variant_id: variant_id, quantity: quantity,
              discount: edit_discount(offer_config, unit_price, discounted, variant["currency"] || session.currency)
            )
          end
          unless result[:success]
            raise CodForm::Errors.build("out_of_stock", fields: { "items" => "error_out_of_stock" }) if result[:code] == "out_of_stock"

            raise CodForm::Errors.build("order_failed")
          end

          total_cents = result[:total_cents] || (session.order_total_cents.to_i + discounted * quantity)
          session.update_columns(
            upsell: upsell.merge("accepted_at" => Time.current.utc.iso8601, "line_added" => true),
            order_total_cents: total_cents, updated_at: Time.current
          )
          tag_order(shop, session.order_id)
          CodForm::FunnelLogger.log(
            shop_id: shop.id, session_token: session.public_id, type: "cf_upsell_accept",
            meta: { "offer_id" => offer.id, "value_cents" => discounted * quantity, "currency" => session.currency }
          )

          {
            "ok" => true,
            "order" => { "id" => session.order_id.to_s, "name" => session.order_name, "total_cents" => total_cents },
            "added" => { "variant_id" => variant_id, "quantity" => quantity, "price_cents" => discounted }
          }
        ensure
          CodForm::Cache.store.delete(lock_key)
        end
      end

      def decline(session:, offer_id:)
        upsell = session.upsell.is_a?(Hash) ? session.upsell : {}
        if upsell["offer_id"].to_s == offer_id.to_s && upsell["accepted_at"].blank? && upsell["declined_at"].blank?
          session.update_columns(upsell: upsell.merge("declined_at" => Time.current.utc.iso8601), updated_at: Time.current)
        end
        { "ok" => true }
      end

      # Price per unit after the offer's discount (integer cents, never negative).
      # fixed_amount is cents off the whole upsell line, like quantity-offer tiers (E.6).
      def discounted_unit_price(offer_config, unit_price_cents, quantity)
        value = offer_config["value"].to_f
        off =
          case offer_config["discount_type"].to_s
          when "percentage" then CodForm::Engine::Money.percent_of(unit_price_cents, value.clamp(0, 100))
          when "fixed_amount" then value.to_i / [quantity.to_i, 1].max
          else 0
          end
        [unit_price_cents.to_i - off, 0].max
      end

      def purchasable?(variant, quantity)
        return false unless variant.is_a?(Hash) && variant["available"] == true
        return true if variant["inventory_policy"].to_s == "continue" || !variant["inventory_quantity"].is_a?(Integer)

        variant["inventory_quantity"] >= quantity.to_i
      end

      private

      # F.6 step 1: this session was offered exactly this upsell, the window is open, not used yet.
      def offered!(session, offer_id)
        upsell = session.upsell.is_a?(Hash) ? session.upsell : {}
        expires_at = begin
          Time.iso8601(upsell["expires_at"].to_s)
        rescue ArgumentError
          nil
        end
        valid = session.order_id.present? && !upsell["offer_id"].nil? && upsell["offer_id"].to_s == offer_id.to_s &&
                expires_at && Time.current < expires_at && upsell["accepted_at"].blank? && upsell["declined_at"].blank?
        raise CodForm::Errors.build("upsell_expired") unless valid

        upsell
      end

      # orderEditAddLineItemDiscount: percentValue, or a PER-UNIT fixedValue.
      def edit_discount(offer_config, unit_price, discounted, currency)
        off = unit_price - discounted
        return nil unless off.positive?

        if offer_config["discount_type"].to_s == "percentage"
          { "type" => "percentage", "value" => offer_config["value"].to_f.clamp(0, 100) }
        else
          { "type" => "fixed_amount", "amount" => CodForm::Engine::Money.to_decimal_string(off), "currency" => currency.to_s }
        end
      end

      def tag_order(shop, order_id)
        ShopifyServices::OrderTagPostService.call(shop, order_id, "codking_upsell")
      rescue StandardError => e
        Rails.logger.warn("[CodForm::UpsellService] tag failed shop_id=#{shop.id} order_id=#{order_id} #{e.class}")
      end
    end
  end
end
