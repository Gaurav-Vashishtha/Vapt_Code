# WS2 — pure-Ruby engines: implementation notes

3 Oct 2026 · covers `ARCHITECTURE.md` sections E, C (schemas), F.3, J.2 and K.2.

## 1. Files

Engines — `app/services/cod_form/engine/` (module `CodForm::Engine`, 27 classes, one per file):

`money` · `postal_matcher` · `cod_rules` · `visibility` · `shipping_rates` · `offers` · `offer_overlap` · `quote` · `cod_fee` · `fraud` · `phone` · `country_schema` · `partial_rules` · `session_token` · `defaults` · `form_config` · `form_validator` · `form_targeting` · `button_config` · `metafield_payload` · `feature_gates` · `cap_resolver` · `otp_policy` · `ab_test` · `thank_you` · `draft_order_builder` · `recovery`

Data — `config/cod_form/countries.json`: IN, PK, MA, CO, PE, DO, HU, RS, AE, SA, EG, ID, PH, MX, TR, RO, PL, ES, IT, PT, FR, DE, GB, US and `default`.

Tests — `test/services/cod_form/engine/`: `*_test.rb` (19 files), `engine_test_helper.rb`, `all.rb`, `run_all.rb`, `fixtures/{phone_cases,postal_cases,quote_cases,validation_cases}.json`.

## 2. Running the tests

```
cd cod-confirm
ruby -Itest test/services/cod_form/engine/quote_test.rb     # one file
ruby test/services/cod_form/engine/all.rb                    # everything (run_all.rb is an alias)
```

No Rails, no gems beyond minitest. Last run: 212 runs, 1435 assertions, 0 failures.

Under the Rails runner the same files work: `engine_test_helper.rb` requires `test_helper` when Rails is present and the engines are then autoloaded.

## 3. Loading (plain Ruby and Zeitwerk)

- Each file defines exactly `CodForm::Engine::<CamelCase file name>`, so Zeitwerk autoloads it.
- Stdlib requires are at the top of each file. Sibling engines are required like this:

  ```ruby
  unless defined?(::Rails)
    require_relative "money"
  end
  ```

  So `require "…/engine/quote"` works in plain Ruby, and under Rails nothing is loaded behind Zeitwerk's back.
- **Do not `require_relative` an engine file from Rails code.** It bypasses Zeitwerk and breaks code reloading in development (the constant goes missing after the first reload). `app/services/cod_form/abandonment/recovery_link.rb` (WS8) currently does `require_relative "../engine/recovery"`; that line should be removed.
- Inside the engines, `Money` and `Phone` resolve to `CodForm::Engine::Money` / `::Phone`, not the money gem. Outside the engines always write the full name.
- No ActiveSupport, no clock, no randomness, no I/O except `CountrySchema.load(path)` (default path `config/cod_form/countries.json`, cached per path).

## 4. Rounding rules

All amounts are integer cents. Arithmetic is exact (`Rational`), never float.

| Operation | Rule |
| --- | --- |
| `Money.percent_of(cents, percent)` | round half up to the cent |
| `Money.round_to_half_unit(cents)` | nearest 50 cents, half up |
| `Money.allocate(total, weights)` | largest remainder; parts always sum to `total` |
| Tier `percentage` | `percent_of(unit_price, v)` **per unit** |
| Tier `unit_price` | `max(unit_price − v, 0)` per unit |
| Tier `fixed_amount` | `v / quantity` (integer division) per unit; charged and displayed discount is `(v / n) × n` |
| Any per-unit discount | capped at the unit price |
| Downsell `percentage` | `percent_of(unit price after the tier, v)` per unit |
| Downsell `fixed_amount` | split across product lines by line total (`allocate`), then per unit by integer division; left-over cents go to lines whose quantity still fits. Never exceeds the value or the merchandise |
| Discount code `percentage` | `percent_of(eligible total after offers, v)`, one order-level amount |
| Discount code `fixed_amount` | the value (cents), capped at the eligible total |
| COD fee `fixed` | `(value × 100 × fx_rate)` half up; when `fx_rate ≠ 1` and the currency is HUF, COP, RSD, PKR, JPY, KRW or CLP, rounded to the whole unit |
| COD fee `percentage` | `round_to_half_unit(percent_of(base, value))`, base = merchandise after all discounts + shipping |

Totals:

```
subtotal_cents          = Σ product lines (unit price × quantity)
discount_total_cents    = Σ (per-unit line discount × quantity) + discount code amount
merchandise_total_cents = subtotal − discount_total + bump lines        (gift lines are 0)
total_cents             = merchandise_total + shipping + COD fee (+ tax when status is "calculated")
savings_cents           = discount_total + Σ (compare-at − unit price) × quantity
```

**Shown total = order total.** `DraftOrderBuilder` sends the same integers: line discounts as `FIXED_AMOUNT` per unit, the code as one order-level `FIXED_AMOUNT`, fee and custom bumps as custom lines, shipping as its own line. `PERCENTAGE` is used on a line only when the tier is a percentage, no downsell is stacked, and `unit_price × percent / 100` is a whole number of cents — otherwise the same discount goes out as `FIXED_AMOUNT`, because Shopify's own rounding of a percentage could differ by a cent. `draft_order_builder_test.rb` recomputes the draft total from the built input and compares it with `quote["total_cents"]`.

## 5. Stacking (OFF-8)

1. Quantity offer — per-unit line discount.
2. Downsell — per-unit line discount on what remains after step 1.
3. Discount code — one order-level amount on what remains after steps 1–2 (product lines and bump lines).

When `general.discounts.codes_combine_with_offers` is false and any product line carries a quantity-offer or downsell discount greater than 0, the code returns `not_combinable` and is not applied. A matched tier with no discount (`none`) does not block a code. Lines whose properties contain a key starting with `_` (bundle apps) never get a tier (OFF-9); the downsell still applies to them.

## 6. Choices where ARCHITECTURE.md was silent or ambiguous

Names, signatures, hash keys and error codes follow the document. The points below are additions or readings; none renames anything.

**Quote input — optional keys beyond E.7**

| Key | Meaning |
| --- | --- |
| `downsell_offer_id` | The downsell in `offers["downsell"]` is applied **only** when this equals its `id`. Without it the downsell is shown, never applied. |
| `page` | Passed to `Visibility` (`product`, `cart`, …). Absent → no page check. |
| `country` | Used for the country check when `address["country"]` is empty. Both empty → no country check yet. |
| `locale` | Picks offer labels; falls back to `default`. |
| `money_format` | For payment option descriptions. |
| `hide_shipping_selector_when_single` | Default true. |
| `tax["unavailable"]` | true → `tax.status = "unavailable"`. |
| `block["message"]` | Overrides the fraud message for the reason. |

**Quote output — keys beyond D.2**

- `eligibility["pending"]` — address inputs a rule is still waiting for.
- `shipping["none_available"]`, `shipping["pending_address"]`, `shipping["message_key"]` (`error_no_shipping` or `shipping_enter_address`). `shipping["message"]` is always nil; the text is a text key.
- `lines[].max_quantity` is **nil when there is no limit** (inventory policy `continue` and no fraud cap). Guard for nil before comparing.
- `discount_code.status` is `"invalid"` (plus `"error"`) when the adapter passed `{"code","error"}`.
- `warnings` may contain `out_of_stock`, `bump_unavailable`, `gift_unavailable`.
- `_draft` = `{"currency","lines","order_discount","shipping","cod_fee"}`; `_fingerprint` = SHA-256 of the canonical JSON of `_draft` and `total_cents`.

**Other readings**

- Thresholds compare against `merchandise_total_cents` (after every discount), as the signature says. The D.2 example value (851360) was computed from the order total and is not reproduced.
- `PostalMatcher` ranges: the code must be all digits **and** as long as the bounds (`1500` does not match `01000-01999`). `A-B` with `A > B` is swapped.
- `CodRules`: with an empty province or zip, an *allow* list is pending at `page`/`quote` and fails at `submit`; a *deny* list is pending before submit and passes at submit (otherwise countries without provinces could never order).
- `ShippingRates`: when no rate qualifies, `none_available` is true even while `pending_address` is true. Custom lines (no product) are neutral for product conditions.
- `Offers.resolve_bumps`: only the first three matching bumps by priority can be selected. A variant bump priced above the variant's price is charged at the variant's price.
- `Offers.apply_discount_code`: `value` of a `fixed_amount` code is **cents**; a percentage is `0..100`.
- `Fraud.check` order: honeypot → too fast → block lists → max quantity → velocity limits. `max_quantity` returns code `limit_reached`. A limit is reached when `count >= max_orders` (count = orders already placed). IP block entries: exact, or IPv4 CIDR; IPv6 is exact match only.
- `Phone`: a leading bare dial code is stripped only when the number is not already a valid national number (so the Italian mobile `391 234 5678` is kept, and `4915112345678` becomes German `15112345678`). `+`/`00` with another country's dial code → `bad_prefix`. New optional rule key `trunk_prefixes` (Hungary `06`).
- `PartialRules.amounts` totals: `subtotal_cents`, `line_discount_cents`, `total_cents`, `cod_fee_cents`. `amount_to_show` (display-only advance) is not applied. `handoff_attributes` reads `cart["lines"]` (quote lines), the same totals and `cart["money_format"]`; the PRE-2 prepaid-discount attribute is left to the caller.
- `CapResolver`: `behaviour`, `grace_orders` and `overage_rate` take the first non-nil value down the whole chain (shop → group rows → plan), then `global`. No matching row → `cap: nil`, `source: "none"`. `orders_count` is the number of orders already counted: on the Free seed 59 → `ok`, 60–69 → `grace`, 70 → `fallback`.
- `FeatureGates`: a row with `enabled: false` is denied even with an override.
- `OtpPolicy`: `risk_based` with an unknown band → not required. `Quote` passes `risk["band"]` as `risk_band` and `otp["risk_band"]` as `target_band`.
- `FormTargeting.pick` takes an extra `is_test:` (default false); `requested_id` is honoured only then.
- `FormValidator.validate` accepts flat values or the D.6 grouping (`contact`/`address`/`fields`/`custom_fields`).
- `OfferOverlap`: an all-products offer next to any other active quantity offer is reported with `product_id: "*"`.
- `Defaults.plan_limits`: the country-group row has `scope_key: nil` and carries the group definition under `country_group`.
- Extra public helpers: `CountrySchema.load`, `.phone_rules`, `.countries`; `Defaults.design`, `.button_preset`, `.global_settings`; `FormConfig.sanitize_html`; `Offers.targets_cart?`, `Offers::MAX_BUMPS_SHOWN`; `Recovery::PARAM`.

## 7. Known limits

- True zero-decimal currencies (JPY, KRW, …): percentage discounts are rounded to the cent of the ×100 convention, not to the whole unit. No launch market is affected.
- `countries.json` province modes and postal patterns for the non-launch countries are generic; province lists themselves are WS3's (`lib/cod_form/geo`).
- Not run under Ruby 3.2 or under Rails here (container has Ruby 3.3, no bundle). The only 3.2-specific feature used is `Regexp.new(pattern, timeout:)`.
