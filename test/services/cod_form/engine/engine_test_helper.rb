# frozen_string_literal: true

# Loads the pure-Ruby engines for plain minitest (no Rails):
#   ruby -Itest test/services/cod_form/engine/<name>_test.rb
# Under the Rails test runner the engines are autoloaded by Zeitwerk instead.
require "json"

if defined?(::Rails)
  booted = ::Rails.respond_to?(:application) && ::Rails.application && ::Rails.application.initialized?
  require "test_helper" unless booted
else
  engine_dir = File.expand_path("../../../../app/services/cod_form/engine", __dir__)
  Dir[File.join(engine_dir, "*.rb")].sort.each { |file| require file }
end

require "minitest/autorun"

module EngineTestHelper
  E = CodForm::Engine
  FIXTURES = File.expand_path("fixtures", __dir__)

  def fixture(name)
    JSON.parse(File.read(File.join(FIXTURES, "#{name}.json"), encoding: "UTF-8"))
  end

  def countries
    @countries ||= E::CountrySchema.load
  end

  # A catalog line as CodForm::CatalogService returns it (E.7).
  def line(overrides = {})
    {
      "key" => "l0", "variant_id" => "44111", "product_id" => "8111", "collection_ids" => ["301"], "vendor" => "Acme",
      "title" => "Widget", "variant_title" => "Blue", "image" => "https://cdn.example.com/w.png", "quantity" => 1,
      "unit_price_cents" => 199_900, "compare_at_cents" => 249_900, "grams" => 500,
      "requires_shipping" => true, "taxable" => true, "gift_card" => false,
      "available" => true, "inventory_quantity" => 10, "inventory_policy" => "deny", "properties" => {}
    }.merge(overrides)
  end

  def quantity_offer(overrides = {})
    {
      "id" => 12, "offer_type" => "quantity", "name" => "Packs", "status" => "active", "priority" => 0,
      "targeting" => { "scope" => "selected", "product_ids" => ["8111"], "collection_ids" => [] },
      "config" => {
        "title" => { "default" => "Buy more, save more" }, "apply_to_higher_quantities" => true,
        "tiers" => [
          { "quantity" => 1, "discount_type" => "none", "value" => 0, "label" => { "default" => "1 pack" } },
          { "quantity" => 2, "discount_type" => "percentage", "value" => 10, "label" => { "default" => "2 packs" } },
          { "quantity" => 3, "discount_type" => "unit_price", "value" => 149_900, "label" => { "default" => "3 packs" } }
        ]
      }
    }.merge(overrides)
  end

  def shipping_rate(overrides = {})
    { "id" => 4, "name" => "Standard delivery", "description" => "2-4 business days", "price_cents" => 149_000,
      "currency" => "HUF", "position" => 0, "active" => true, "source" => "manual", "conditions" => {} }.merge(overrides)
  end

  def quote_input(overrides = {})
    {
      "currency" => "HUF", "stage" => "quote", "lines" => [line],
      "address" => { "country" => "HU", "province" => "BU", "city" => "Budapest", "zip" => "1051" },
      "contact" => { "phone_digits" => "36301234567", "phone_national" => "301234567", "email" => "anna@example.com" },
      "general" => E::Defaults.general, "fraud" => E::Defaults.fraud, "rules" => {},
      "shipping_rates" => [shipping_rate], "selected_shipping_rate_id" => nil,
      "offers" => { "quantity" => [], "bumps" => [], "downsell" => nil, "thresholds" => [] },
      "selected_bumps" => [], "bump_catalog" => {}, "discount_code" => nil,
      "cod_fee" => { "enabled" => false, "mode" => "fixed", "value" => 0, "label" => "", "taxable" => false, "fx_rate" => 1.0 },
      "tax" => { "prices_include_tax" => true, "calculated" => nil },
      "partial_rules" => [], "risk" => nil,
      "otp" => { "shop_enabled" => false, "mode" => "before_order", "risk_band" => "medium", "verified" => false },
      "block" => { "blocked" => false, "reason" => nil }, "is_test" => false
    }.merge(overrides)
  end

  # Total a Shopify draft order built from the DraftOrderInput would have (before tax), in cents.
  def draft_total_cents(input)
    to_cents = ->(value) { (Rational(value.to_s) * 100).round }
    total = 0
    input["lineItems"].each do |item|
      quantity = item["quantity"]
      if item["variantId"]
        raise "test needs a price for #{item['variantId']}" unless @variant_prices && @variant_prices[item["variantId"]]

        unit = @variant_prices[item["variantId"]]
        discount = item["appliedDiscount"]
        line = unit * quantity
        if discount
          line -= discount["valueType"] == "PERCENTAGE" ? (Rational(line) * Rational(discount["value"].to_s) / 100).round : to_cents.call(discount["value"]) * quantity
        end
        total += line
      else
        total += to_cents.call(item["originalUnitPriceWithCurrency"]["amount"]) * quantity
      end
    end
    total -= to_cents.call(input["appliedDiscount"]["value"]) if input["appliedDiscount"]
    total += to_cents.call(input["shippingLine"]["priceWithCurrency"]["amount"]) if input["shippingLine"]
    total
  end
end
