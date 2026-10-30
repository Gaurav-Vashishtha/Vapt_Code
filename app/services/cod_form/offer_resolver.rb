# frozen_string_literal: true

module CodForm
  # Loads the shop's active offers for a cart, applies feature gates, the schedule and the
  # A/B assignment, and returns the "offers" input of CodForm::Engine::Quote (ARCHITECTURE.md
  # F.1, E.7) plus the session's A/B assignments.
  class OfferResolver
    GATE_BY_TYPE = {
      "quantity" => "quantity_offers", "bump" => "order_bumps", "downsell" => "downsell",
      "upsell" => "upsell", "threshold" => "threshold_offers",
      # Pre-purchase upsells ride on the order-bump plan gate.
      "pre_upsell" => "order_bumps",
      # Bundles ride on the quantity-offer plan gate.
      "bundle" => "quantity_offers"
    }.freeze
    MAX_BUNDLES = 5
    # Rules whose products are priced for a session: the popup shows one, the cart value decides which.
    MAX_PRE_UPSELL_RULES = 3

    Result = Struct.new(:offers, :ab_assignments, :upsell, :bump_catalog, keyword_init: true)

    class << self
      # lines: E.7 line hashes. assignments: {"<ab_test_id>" => "<variant key>"} already held by
      # the session / echoed by the browser. flags: CodForm::Gates.flags(shop).
      def call(shop:, lines:, client_id:, assignments: nil, flags: nil, country: nil)
        flags ||= CodForm::Gates.flags(shop)
        all = CodForm::Offer.where(shop_id: shop.id).active_now.ordered.map(&:to_engine_hash)
        all = all.select { |offer| flags[GATE_BY_TYPE[offer["offer_type"]]] == true }
        all, ab = apply_ab_tests(shop, all, client_id, assignments, flags)

        in_cart = all.select { |offer| CodForm::Engine::Offers.targets_cart?(offer, lines) }
        bumps = in_cart.select { |o| o["offer_type"] == "bump" }.first(CodForm::Engine::Offers::MAX_BUMPS_SHOWN)
        pre_upsells = CodForm::Engine::PreUpsells.for_cart(offers: all, lines: lines).first(MAX_PRE_UPSELL_RULES)
        bundles = CodForm::Engine::Bundles.for_cart(offers: all, lines: lines).first(MAX_BUNDLES)

        Result.new(
          offers: {
            "quantity" => in_cart.select { |o| o["offer_type"] == "quantity" },
            "bumps" => bumps,
            "downsell" => in_cart.find { |o| o["offer_type"] == "downsell" },
            "thresholds" => in_cart.select { |o| o["offer_type"] == "threshold" },
            "pre_upsells" => pre_upsells,
            "bundles" => bundles
          },
          ab_assignments: ab,
          upsell: in_cart.find { |o| o["offer_type"] == "upsell" },
          bump_catalog: bump_catalog(shop, bumps, in_cart, country, pre_upsells, bundles.select { |b| b.dig("config", "show_in_form") != false })
        )
      end

      private

      # Offers that are variants of a running test: only the assigned variant's offer stays.
      # A variant with offer_id nil ("show nothing") removes every offer of the test.
      def apply_ab_tests(shop, offers, client_id, assignments, flags)
        test_ids = offers.map { |o| o["ab_test_id"] }.compact.uniq
        return [offers, {}] if test_ids.empty?

        tests = flags["ab_tests"] == true ? CodForm::AbTest.where(shop_id: shop.id, id: test_ids).running.to_a : []
        running = tests.to_h { |test| [test.id, test] }
        held = assignments.is_a?(Hash) ? assignments : {}
        result = {}

        kept = offers.select do |offer|
          test = running[offer["ab_test_id"]]
          # Not part of a running test (or the gate is off): the offer stands on its own.
          next true if test.nil?

          key = result[test.id.to_s] ||= assign(test, held[test.id.to_s], client_id)
          variant = Array(test.variants).find { |v| v.is_a?(Hash) && v["key"].to_s == key.to_s }
          !variant.nil? && variant["offer_id"].to_s == offer["id"].to_s
        end
        [kept, result.compact]
      end

      def assign(test, held_key, client_id)
        return held_key.to_s if test.variant_keys.include?(held_key.to_s)

        CodForm::Engine::AbTest.assign(test: test.to_engine_hash, seed: client_id.to_s)
      end

      # {"<variant id>" => catalog line} for variant bumps, free-gift thresholds and the products of
      # the pre-purchase upsell rules.
      def bump_catalog(shop, bumps, in_cart, country, pre_upsells = [], bundles = [])
        ids = bumps.select { |o| o.dig("config", "kind").to_s == "variant" }.map { |o| o.dig("config", "variant_id").to_s }
        ids += in_cart.select { |o| o["offer_type"] == "threshold" && o.dig("config", "kind").to_s == "free_gift" }
                      .map { |o| o.dig("config", "gift_variant_id").to_s }
        ids += CodForm::Engine::PreUpsells.variant_ids(pre_upsells)
        ids += CodForm::Engine::Bundles.variant_ids(bundles)
        ids = ids.reject(&:empty?).uniq
        return {} if ids.empty?

        CodForm::CatalogService.variants(shop, ids, country: country)
      rescue StandardError => e
        Rails.logger.warn("[CodForm::OfferResolver] bump catalog failed shop_id=#{shop.id} #{e.class}")
        {}
      end
    end
  end
end
