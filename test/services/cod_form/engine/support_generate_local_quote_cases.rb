# Writes the parity cases of the storefront's instant estimate (localQuote in
# payment-customization-js/storefront/cod-form/src/core/quote.js): for each case the engine's
# own answer for a new address / shipping choice, which the browser must reproduce from "local".
#   ruby test/services/cod_form/engine/support_generate_local_quote_cases.rb <out.json>
require_relative "engine_test_helper"
include EngineTestHelper
E = CodForm::Engine
rates = [
  shipping_rate("id" => 1, "name" => "Budapest courier", "price_cents" => 99_000, "position" => 0, "conditions" => { "provinces" => ["HU-BU"] }),
  shipping_rate("id" => 2, "name" => "Standard", "price_cents" => 149_000, "position" => 1, "conditions" => { "countries" => ["HU"] }),
  shipping_rate("id" => 3, "name" => "Express", "price_cents" => 299_000, "position" => 2, "conditions" => {}),
  shipping_rate("id" => 4, "name" => "Heavy only", "price_cents" => 1, "position" => 0, "conditions" => { "weight_min_grams" => 99_999 }),
  shipping_rate("id" => 5, "name" => "Serbia", "price_cents" => 59_000, "position" => 0, "conditions" => { "countries" => ["RS"] })
]
fees = {
  "none" => { "enabled" => false, "mode" => "fixed", "value" => 0, "label" => "", "taxable" => false, "fx_rate" => 1.0 },
  "fixed" => { "enabled" => true, "mode" => "fixed", "value" => 490, "label" => "COD fee", "taxable" => false, "fx_rate" => 1.0 },
  "pct" => { "enabled" => true, "mode" => "percentage", "value" => 2.5, "label" => "COD fee", "taxable" => false, "fx_rate" => 1.0 },
  "pct_odd" => { "enabled" => true, "mode" => "percentage", "value" => "1.37", "label" => "COD fee", "taxable" => false, "fx_rate" => 1.0 }
}
addresses = [
  { "country" => "HU", "province" => "BU" }, { "country" => "HU", "province" => "HU-BU" }, { "country" => "HU", "province" => "PE" },
  { "country" => "HU", "province" => "" }, { "country" => "RS", "province" => "" }, { "country" => "CO", "province" => "DC" }, { "country" => "", "province" => "" }
]
cases = []
fees.each do |fee_name, fee|
  [{}, { "tax" => { "prices_include_tax" => false, "calculated" => { "amount_cents" => 53_973, "lines" => [] } } }].each do |extra|
    base = E::Quote.build(quote_input({ "shipping_rates" => rates, "cod_fee" => fee, "lines" => [line("quantity" => 2)] }.merge(extra)))
    addresses.each do |address|
      [nil, 3].each do |selected|
        full = E::Quote.build(quote_input({ "shipping_rates" => rates, "cod_fee" => fee, "lines" => [line("quantity" => 2)],
                                            "address" => address.merge("city" => "X", "zip" => "1051"), "selected_shipping_rate_id" => selected }.merge(extra)))
        cases << { "name" => "#{fee_name} #{extra.empty? ? 'incl' : 'tax'} #{address.values.join('/')} sel=#{selected.inspect}",
                   "quote" => base.slice("local", "shipping", "cod_fee", "shipping_cents", "total_cents"), "country" => address["country"], "province" => address["province"], "selected" => selected,
                   "expected" => { "shipping" => full["shipping"].slice("rates", "selected_id", "price_cents", "none_available", "pending_address", "hide_selector", "message_key"),
                                   "shipping_cents" => full["shipping_cents"], "fee_cents" => full["cod_fee"]["amount_cents"], "fee_enabled" => full["cod_fee"]["enabled"],
                                   "total_cents" => full["total_cents"] } }
      end
    end
  end
end
none = E::Quote.build(quote_input("lines" => [line("requires_shipping" => false)]))
raise "local must be nil without shipping" unless none["local"].nil?
File.write(ARGV[0], JSON.generate(cases))
puts cases.size
