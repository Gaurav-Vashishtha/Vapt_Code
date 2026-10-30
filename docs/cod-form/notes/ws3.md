# WS3 — storefront API, order creation, security, routes

3 Oct 2026 · covers ARCHITECTURE.md sections D.0–D.13, F, J.1/J.2 (gates, cap) and K.3.

## 1. Files

### Created

| Path | What |
| --- | --- |
| `app/controllers/api/form/base_controller.rb` | `Api::Form::BaseController < ActionController::API`: body parse (text/plain JSON, 64 KB), shop, origin, module, token; error envelope |
| `app/controllers/api/form/{sessions,quotes,contacts,otp,orders,handoffs,upsells,events,geo}_controller.rb` | one per endpoint group (D.1–D.11) |
| `app/services/cod_form/errors.rb` | error catalogue (code → HTTP, message key, fallback), `ApiError`, `InvalidItem`, `token_failure` — **pure Ruby** |
| `app/services/cod_form/origin_guard.rb` | origin check — host matching is **pure Ruby** |
| `app/services/cod_form/rate_limiter.rb` | `hit!(key, limit:, period:)` on `Rails.cache`; key builders are **pure Ruby** |
| `app/services/cod_form/availability.rb`, `gates.rb`, `cap_service.rb` | K.9 contracts |
| `app/services/cod_form/catalog_service.rb` | variant prices/stock from Shopify (cached 60 s), `shop_info`, `admin_query` (the one Admin GraphQL entry point of the form services), `geo_dataset` |
| `app/services/cod_form/offer_resolver.rb`, `discount_code_service.rb`, `risk_service.rb`, `fraud_adapter.rb`, `quote_service.rb`, `tax_service.rb`, `customer_resolver.rb`, `otp_service.rb`, `order_service.rb`, `handoff_service.rb`, `upsell_service.rb`, `order_webhook_hook.rb` | F.1 |
| `app/services/cod_form/adapters/{rules_adapter,cod_fee_adapter,partial_rules_adapter,money_format_adapter}.rb` | `Setting` / `PartialRuleSet` / `Shop` → engine hashes (`MoneyFormatAdapter.parse` is pure) |
| `app/services/shopify_services/order_edit_add_line_service.rb` | order edit: begin → add variant → line discount → commit (F.6) |
| `app/workers/cod_form/create_order_job.rb`, `session_purge_job.rb` | ORD-9 background half; retention |
| `config/initializers/cod_form.rb` | Zeitwerk `collapse` of `adapters/`, `Setting.after_commit` → metafield re-sync, ENV warnings |
| `lib/cod_form/geo/{PK,MA,CO,PE,DO,HU,RS,IN}.json` | provinces + main cities per province |
| `test/services/cod_form/*_test.rb`, `test/services/cod_form/support/storefront_smoke_harness.rb` | see section 6 |
| `docs/cod-form/snippets/ws3-schedule.yml.md` | `CodForm::SessionPurgeJob` (already merged into `config/schedule.yml` by WS8) |

### Edited (existing files)

`app/services/shopify_services/cod_order_create_service.rb`, `app/controllers/api/cod_orders_controller.rb`, `app/workers/order_confirmation_create_job.rb`, `config/routes.rb`, `config/initializers/rack_attack.rb`, `config/initializers/filter_parameter_logging.rb`. Details in section 4.

## 2. Endpoints

All under `/api/form`, `POST`, `Content-Type: text/plain`, JSON string body, `?shop=<myshopify domain>`.

| Route | Action | Token | Notes |
| --- | --- | --- | --- |
| `POST session` | `sessions#create` | no | fallbacks are `200 {"ok":true,"fallback":…,"token":null}` |
| `POST quote` | `quotes#create` | yes | echoes `seq`; ineligibility is data in a 200 |
| `POST contact` | `contacts#create` | yes | saves contact / partial address only |
| `POST otp/send` | `otp#send_code` | yes | bypass → `{"ok":true,"sent":false,"bypass":true}` |
| `POST otp/verify` | `otp#verify` | yes | wrong code → 422 `otp_invalid` + `attempts_left` |
| `POST orders` | `orders#create` | yes | 201 / 200 replay / 202 processing |
| `POST orders/status` | `orders#status` | yes | 200 / 202 / 502 (`order_error`) |
| `POST handoff` | `handoffs#create` | yes | partial / prepaid |
| `POST upsell_accept` | `upsells#accept` | yes | `accept: false` records the decline |
| `POST events` | `events#create` | optional | always 204 |
| `GET geo/:country` | `geo#show` | no | `Cache-Control: public, max-age=86400` |
| `GET geo/:country/postal/:code` | `geo#postal` | no | same cache header |

Error envelope and codes are exactly D.0.3; one extra code, `internal_error` (HTTP 500), is used for unexpected exceptions (the client treats any 5xx on `session` as a fallback).

## 3. Security model

- **Token.** `CodForm::Engine::SessionToken` (WS2), secret = `Rails.application.key_generator.generate_key("cod_form_session_v1", 32)`. `authenticate_session!` rejects: bad signature / malformed / wrong shop (`shp` ≠ the shop of `?shop=`) → 401 `invalid_token`; expired token **or** expired / `expired`-status row → 401 `token_expired`; token `t` flag ≠ row `is_test` → `invalid_token`.
- **One order per session.** `OrderService#claim!` is one SQL `UPDATE … WHERE id = ? AND order_id IS NULL AND status IN (orderable)`. Losers get the stored order (200) or 409 `already_processing`. A session stuck in `ordering` for more than 120 s (request died) can be claimed again; if the `orders/create` webhook already saw the order, `OrderWebhookHook` left its id in `tracking.webhook_order_id` and the next submit **adopts** that order instead of creating a second one.
- **After Shopify created the order nothing can reset the session:** the response build, persist (3 attempts), usage, events and upsell are each rescued. If the row cannot be written the session stays in `ordering` (never back to `open`).
- **Server-side prices.** Every quote and the submit are built from `CatalogService` (Shopify contextual prices) through `Engine::Quote`; `expected_total_cents` is only compared. Client `cart_line_price_cents` is used solely for bundle-cart detection.
- **OTP is bound to the phone.** `QuoteService.otp_verified_for?` compares the verified digits with the submitted phone (a different number → 428 `otp_required`). Found and fixed by the smoke test.
- **Origin.** `OriginGuard`: myshopify domain, host of `shops.primary_domain`, `shop_config.allowed_origins`, `*.shopifypreview.com`, localhost only with `COD_FORM_ALLOW_LOCALHOST=true` / development. Missing Origin and Referer → rejected.
- **Throttles** (Rack::Attack, D.0.4) plus `RateLimiter`: `codf:otp:<shop>:<phone>` 5/600 s, `codf:order:<shop>:<phone>` 5/600 s, OTP verify 10/600 s per session, discount lookups 20/600 s per session.
- **Bots.** Honeypot `codkf_company_url`, `min(elapsed_ms, token age) < min_submit_seconds` → 422 `bot_suspected` with the generic message, rejection logged.
- **Logs.** Only shop id, session public id, order id, codes and exception classes. The body is never logged (text/plain is not parsed into `params`); unexpected exceptions log class + file:line, not the message.

## 4. Existing behaviour unchanged — how it is guaranteed

**`cod_order_create_service.rb`** (+93 / −41)

- New keyword `form_context: nil` on `initialize` and `self.call`. With `nil` every branch added is skipped.
- Legacy draft input: verified byte-identical. A harness loaded the original file and the edited file with the same stubs, ran three representative Express payloads (line discounts, cart discounts, percentage discount, COD fee, shipping details as Hash and as String, OTP verified or not, campaign attribution) and compared `Marshal.dump(variables)` → identical. The F3 defect (`@shipping_rate_details`) is untouched.
- The mutation selection gained `totalPriceSet { presentmentMoney { amount currencyCode } }` (F.4). This changes the selection, not the input.
- Return hash gained `draft_total_cents`, `draft_order_id`, and `code:` on errors (`draft_user_errors`, `complete_failed`, `total_changed`, `exception`). `Api::CodOrdersController` reads none of them.
- Form path only: `variables = {input: form_context[:draft_input]}`; draft total vs `expected_total_cents` beyond `tolerance_cents` → `draftOrderDelete` + `code: "total_changed"`; `add_verification_tag_if_verified` and `report_purchase_to_meta_if_configured` are skipped.
- PII removed on both paths: `variables.inspect` / `resp.inspect`, the six shipping debug lines, the per-order success Slack post, `Payload:` and `Result: …inspect` in the failure post, the backtrace in the exception post.

**`api/cod_orders_controller.rb`** (+8 / −0): after the shop lookup, `CodForm::OriginGuard.legacy_allowed?(shop, request)` — logs a mismatch and continues; rejects (403) only with `COD_ORDERS_ORIGIN_ENFORCE=true`. It rescues everything and returns true on error.

**`order_confirmation_create_job.rb`** (+6 / −1)

```
+ params = CodForm::OrderWebhookHook.normalize(params, shop)        # after Shop.find
+ CodForm::OrderWebhookHook.after(shop, params)                      # verified branch, before `return`
+ CodForm::OrderWebhookHook.after(shop, params)                      # normal branch, after call_partial_edit_job
  CodFeesService condition … && !params['_codk_form']
```

`normalize` returns the same object unless the order carries `_codkFormSessionId` of a session of this shop that owns the order; `after` returns immediately without that attribute. Both rescue `StandardError`.

**`config/routes.rb`** (+79 / −0), **`rack_attack.rb`** (+95 / −0), **`filter_parameter_logging.rb`** (+8 / −0): additions only. The `req/ip` throttle is untouched; non-form paths keep Rack::Attack's default 429 body.

## 5. Routes and snippets merged

- Own: the `namespace :form` block inside `namespace :api` (D.13).
- `ws1-routes.md` — merged: `namespace :cod_form` inside `namespace :admin`, after `sms_provider_country_mappings`.
- `ws6-routes.md` — merged: the `/cod_form` API scope, the two public routes (`/cod_form/preview_frame`, `/cod_form/google/callback`), the four page routes inside the `settings_pages` lambda, `/usage-analytics/cod-form`. The text equals D.16, so nothing separate was pre-added.
- No route snippet from WS8 or any other stream existed (polled after finishing; `ws4-*.md` are not routes).
- `ws3-schedule.yml.md` was merged into `config/schedule.yml` by WS8.

## 6. Verification

- `ruby -c` on all 65 Ruby files touched or loaded here: OK. The 8 geo JSON files parse.
- Plain minitest, no Rails:

| Test | Result |
| --- | --- |
| `ruby test/services/cod_form/errors_test.rb` | 10 runs, 50 assertions, 0 failures |
| `ruby test/services/cod_form/session_token_guard_test.rb` (tampered payload / signature, other secret, expiry, wrong shop, forged test flag, malformed) | 11 runs, 32 assertions, 0 failures |
| `ruby test/services/cod_form/origin_guard_test.rb` | 13 runs, 41 assertions, 0 failures |
| `ruby test/services/cod_form/rate_limiter_test.rb` | 11 runs, 27 assertions, 0 failures |
| `ruby test/services/cod_form/money_format_adapter_test.rb` | 7 runs, 11 assertions, 0 failures |
| `ruby test/services/cod_form/geo_dataset_test.rb` | 7 runs, 2656 assertions, 0 failures |

- `ruby test/services/cod_form/storefront_api_smoke_test.rb` — 18 runs, 319 assertions, 0 failures. It drives the **real** controllers, services and engines through ActionDispatch with real ActiveSupport / ActionPack / rack-attack and in-memory stand-ins for the models, Shopify and the WS8 entry points (stand-ins live only in `test/services/cod_form/support/`). Run standalone with `bundle exec ruby …`; inside `rails test` it skips itself. It is **not** a substitute for a test on a real database and store: SQL, ActiveRecord type casting and every Shopify call are faked.
- Not verified here: app boot, Zeitwerk eager load, the GraphQL documents against the 2025-07 schema dump. The documents were checked against the current Admin schema with Shopify's validator (all valid; four deprecation notices: `ProductVariant.image`, `Product.featuredImage`, `DraftOrder.totalPrice` (existing), `customerSelection`).

## 7. Engine and model methods called

**WS2 engines:** `SessionToken.issue / verify`; `Quote.build` (extra input keys `page`, `locale`, `downsell_offer_id`, `money_format`, `hide_shipping_selector_when_single`, `tax.unavailable`, `block.message`); `DraftOrderBuilder.build`; `Fraud.check / mask`; `Phone.validate`; `CountrySchema.for / phone_rules`; `FormValidator.validate`; `FormTargeting.pick(…, is_test:)`; `FormConfig.for_storefront`; `Offers.match_quantity_offer / targets_cart?` and `Offers::MAX_BUMPS_SHOWN`; `PartialRules.handoff_attributes` (rule nil for Pay online); `ThankYou.resolve`; `Money.format / to_decimal_string / percent_of`; `FeatureGates.map`; `CapResolver.resolve / state`; `AbTest.assign`; `Defaults.general / fraud`.

**WS1 models:** `ShopConfig.for`, `#cod_form_mode?`, `#module_enabled?`, `#preview_token_matches?`, scope `cod_form_mode`; `GlobalSetting.current` (`kill_switch`, `async_orders`, `at_cap_behaviour`, `grace_orders`, `usage_notice_thresholds`, `#rate_limits`); `Session` constants and scope `live`; `Form.default_for`, scopes `active.ordered`; `Offer.active_now.ordered`, `#to_engine_hash`; `AbTest.running`, `#variant_keys`, `#to_engine_hash`; `ShippingRate.active.ordered`, `#to_engine_hash`; `BlockEntry.normalize`; `Rejection.create!`; `OrderUsage.for / increment!`; `PlanLimit.active`, `#to_engine_hash`; `CountryGroup.for_country`; `FeatureGate#to_engine_hash`; `Integration` (rabbitpay row). `Session#mark_ordered!` is **not** used: the order row is written with `update_columns` so a model validation can never undo an order that exists in Shopify.

**WS8 / WS6:** `FunnelLogger.log`, `EventIngestService.call`, `PostOrderJob.perform_async`, `Tracking::ServerDispatchJob.perform_async(id, "initiate_checkout")`, `Tracking::PixelResolver.for`, `CapNotifyJob`, `OtpUnavailableNotifyJob`, `Abandonment::RecoveryService.prefill`, `MetafieldSyncJob.perform_async`.

## 8. ENV / config

| Name | Default | Effect |
| --- | --- | --- |
| `COD_FORM_ORIGIN_ENFORCE` | enforce | `false` → origin mismatch is only logged |
| `COD_FORM_ALLOW_LOCALHOST` | off | `true` → `localhost` / `127.0.0.1` origins accepted (harness) |
| `COD_ORDERS_ORIGIN_ENFORCE` | off | `true` → legacy `/api/cod_orders` rejects foreign origins |
| `COD_FORM_EXTENSION_UUID` | – | accepted prefix of `assets_base` |
| `APP_HOST` | existing | checked at boot (warning only) |

Rate-limit overrides: `cod_form_global_settings.settings["rate_limits"] = {"codf/session/ip": {"limit": 60}}`, read on the first request after boot (restart to change). Only `limit` can be overridden, not the period.

## 9. Manual test plan

```sh
API=https://<app host>/api/form; SHOP=brand.myshopify.com; O='Origin: https://brand.hu'; CT='Content-Type: text/plain;charset=UTF-8'

# 1 session → token, form, quote
curl -s "$API/session?shop=$SHOP" -H "$O" -H "$CT" -d '{"source":"product","locale":"hu","country":"HU","items":[{"variant_id":"44111","quantity":2}],"client_id":"t1","device":"mobile"}'
# 2 quote
curl -s "$API/quote?shop=$SHOP" -H "$O" -H "$CT" -d '{"token":"<T>","seq":1,"items":[{"variant_id":"44111","quantity":2}],"address":{"country":"HU","city":"Budapest","zip":"1051"},"contact":{"phone":"301234567"},"shipping_rate_id":4,"want_tax":false}'
# 3 contact
curl -s "$API/contact?shop=$SHOP" -H "$O" -H "$CT" -d '{"token":"<T>","contact":{"phone":"301234567","email":""},"country":"HU"}'
# 4 OTP
curl -s "$API/otp/send?shop=$SHOP" -H "$O" -H "$CT" -d '{"token":"<T>","phone":"301234567","country":"HU","channel":"sms"}'
curl -s "$API/otp/verify?shop=$SHOP" -H "$O" -H "$CT" -d '{"token":"<T>","phone":"301234567","country":"HU","code":"4821"}'
# 5 order (wait > min_submit_seconds after the session call)
curl -s "$API/orders?shop=$SHOP" -H "$O" -H "$CT" -d '{"token":"<T>","idempotency_key":"<SID>:1","items":[{"variant_id":"44111","quantity":2}],"contact":{"first_name":"Anna","phone":"301234567"},"address":{"country":"HU","city":"Budapest","zip":"1051","address1":"Fo utca 1"},"shipping_rate_id":4,"payment_option_id":"cod","expected_total_cents":<total>,"elapsed_ms":20000,"codkf_company_url":""}'
curl -s "$API/orders/status?shop=$SHOP" -H "$O" -H "$CT" -d '{"token":"<T>"}'
# 6 hand-off, upsell, events, geo
curl -s "$API/handoff?shop=$SHOP" -H "$O" -H "$CT" -d '{"token":"<T>","kind":"prepaid","reason":"blocked","contact":{"phone":"301234567"},"address":{"country":"HU"},"items":[{"variant_id":"44111","quantity":2}]}'
curl -s "$API/upsell_accept?shop=$SHOP" -H "$O" -H "$CT" -d '{"token":"<T>","offer_id":33,"accept":true}'
curl -s -o /dev/null -w '%{http_code}\n' "$API/events?shop=$SHOP" -H "$O" -H "$CT" -d '{"client_id":"t1","events":[{"type":"cf_button_view","at":"2026-10-03T09:58:01Z","meta":{"page":"product"}}]}'
curl -si "$API/geo/PK?shop=$SHOP" -H "$O" | head -20
curl -s "$API/geo/IN/postal/411001?shop=$SHOP" -H "$O"
```

Checks to make on a development store:

1. Repeat the order call (same and new key) → 200 with the same body, one Shopify order.
2. Order total in Shopify = `expected_total_cents`; fee is its own line titled with the COD label; tags `COD`, `Created-From-COD-King`, `codking_form`; note attributes `_codkFormSessionId`, `_codkFormId`, `_codkCodFee`.
3. `orders/create` webhook: an `OrderConfirmation` with `source_name = codking_form`, messages sent as for a checkout COD order with `skip_draft_order` at its default (true); no "COD-Fees" line added; `cod_fee` = `_codkCodFee`.
4. A hand-made draft order (no `_codkFormSessionId`) still gets `COD-SKIP-VERIFICATION`.
5. Express: place an order through `/api/cod_orders` and compare the draft order with one from before the deploy.
6. Token of shop A against `?shop=B` → 401; without `Origin` → 403; 11th `otp/send` from one IP in 10 minutes → 429 JSON envelope.
7. Shop with tax-exclusive prices: `want_tax: true` → `tax.status: "calculated"`, order total equal.
8. Kill switch on → `session` answers `fallback: "kill_switch"`, other calls 503.
9. Partial hand-off → checkout order gets `codking_form` + `codking_form_partial`, usage +1.

## 10. Deviations from ARCHITECTURE.md

| Topic | Document | Here | Why |
| --- | --- | --- | --- |
| `OrderWebhookHook.normalize` | `normalize(params)`; match `session.order_id == params['id']` | `normalize(params, shop)`; also matches a **draft-order** webhook whose session is in `ordering` with no order id yet | the webhook can arrive before `OrderService` stores the order id; without this the order would be skipped by `skip_draft_order`. `shop` scopes the session lookup |
| `OrderWebhookHook.after` call sites | "at the end of `#perform`" | two calls (verified branch returns early) | both exits must run it |
| `filter_parameters` | symbols `:phone, :email, …` | one anchored regex with the same names (+ `preview_token`, `recovery_token`) | the file's existing rule: anchored keys, so `otp` does not redact `otp_wait_time` nor `token` redact `store_front_token` in admin logs |
| Rate-limit overrides | "read once at boot" | read on the first request after boot | an initializer must not query a table that may not exist yet |
| `Availability.call` | `{available:, fallback:}` | plus `mode_off: true` when only the mode is off; optional `config:` | staff preview sessions before go-live (`test_only`) |
| `QuoteService` | `call → quote` | `call` (public quote) and `build` (Result with the full quote, lines, offers) | `OrderService` needs `_draft` |
| Total mismatch after `draftOrderCreate` | 409 with Shopify's totals | same, and Shopify's total is remembered per cart + destination (`cart_snapshot.confirmed_total`) so the next quote and submit accept it | otherwise the buyer loops on `total_changed` forever (tax unavailable, rounding) |
| Stored order response | – | `quote_snapshot["order_response"]` (removed by the purge job after 30 days) | replays and D.7 return the same body |
| `session.mark_ordered!` | F.2 step 13 | `update_columns` | see section 7 |
| Geo datasets | cities "only where a dataset is approved" | main cities for all eight countries (`cities.mode: "by_province"`) | workstream brief |
| Geo files | – | extra key `shopify_provinces` | see open issue 1 |
| Tax call input | same input as the order | same lines, discounts, shipping, fee; address reduced to country, province, city, zip; no contact | data minimisation; tax does not depend on the street in these markets |
| Events endpoint | – | origin / body errors also answer 204 | "always 204" |
| `adapters/*.rb` class names | `CodForm::RulesAdapter` … | same names; the directory is collapsed in `config/initializers/cod_form.rb` | Zeitwerk would otherwise expect `CodForm::Adapters::…` |
| Async orders | steps 11–17 in the job | the job re-runs steps 6–10 too (fresh quote), skipping bot / fraud / limiter | the job has only the session row |
| OTP verify | – | at most 5 wrong codes per send (`otp_attempts_exceeded`) | brute-force bound; not specified |
| Step order in F.2 | validation (3) before re-quote (6) | the quote is built before validation (it also normalises phone and address); rejections are still raised in the documented order | one normalisation path |

## 11. Open issues for the integrator / reviewer

1. **Province codes of countries Shopify has no province list for** (PK, MA, DO, HU, RS use ISO 3166-2 codes; CO, IN and PE use what I believe are Shopify's codes, PE with the `PE-` prefix). For `shopify_provinces: false` the order sends no `provinceCode` and puts the province name in `address2`. None of these codes could be checked against Shopify's country data here — verify on a store before launch, especially PE.
2. **PE province prefix.** WS2's engines strip one leading `"<country>-"` from a province. For Peru the buyer's province is `PE-LIM`: `ShippingRates` and `CodRules` then compare `LIM`, so a rate condition for Lima is stored as `PE-LIM` (not `PE-PE-LIM`) and a Limit COD province entry as `LIM` or `PE-LIM`. For the order, `OrderService.draft_address` doubles the prefix so `DraftOrderBuilder` sends `provinceCode: "PE-LIM"`. This rests on issue 1 (that Shopify's Peru codes carry the prefix).
3. **COD fee in another currency.** `CodFeeAdapter.fx_rate` uses `ExchangeRateBank`; when no rate is available it logs and uses 1.0 (the shop-currency amount is charged at face value). Decide whether to disable the fee instead.
4. **Fixed-amount discount codes / minimums** in a currency other than the quote currency are reported as `unsupported`.
5. **PRE-2 prepaid-discount attribute** is not added by the hand-off (WS2 leaves it to the caller; the attribute name is not in the document).
6. **`_codkBundleMode` / dummy variant**: when the shop has no `partial_dummy_variant_id`, the hand-off creates it with `PartialDummyVariantCreateService` inside the request (slow first call).
7. **Duplicate-order window.** If a submit dies after Shopify created the order, the buyer retries after 120 s, and the webhook has not arrived by then, a second order is created. The adopt path closes the common case only.
8. **Shopify read timeout 12 s** (F.2) is not set: the existing services configure no timeout and `ShopifyAPI` 9.5 has no per-call option in the idiom used.
9. **Async wait** blocks a web thread for up to 8 s (as specified). Leave `async_orders` off unless needed.
10. **`Shop.find_by_shopify_domain_with_cache`** returns a cached `Shop`; `shop.setting` is then read per request. A changed `primary_domain` is seen only after that cache entry expires.
11. **Event id.** `event_ids.initiate_checkout` uses the full session id (`codkf_<uuid>_ic`), matching WS8's `EventMap`; the D.1 example shows a shortened id.
12. **Rack::Attack `req.ip`** behind a proxy is whatever the existing setup yields; the per-IP limits inherit that.
13. `countries` in the session response takes names from the `provinces` table (`country_name`); a country without rows there is named by its code.
