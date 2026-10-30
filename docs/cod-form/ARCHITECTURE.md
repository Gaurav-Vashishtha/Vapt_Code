# COD King — COD Form: Architecture

Status: **FINAL** for implementation · 3 Oct 2026 · covers P1 + P2 + P3 of `docs/cod-form/SPEC.md` · product decisions of `docs/cod-form/PM_DECISIONS.md` are applied throughout

This document is the contract between eight parallel workstreams (section K). Field names, routes, JSON keys, class names and file paths here are **normative**: copy them, do not rename them. Where this document and the spec differ, this document wins for naming; the spec wins for behaviour.

Repositories (paths as mirrored in `/home/claude/work`):

- `cod-confirm/` — Rails 7.2 backend + React 18 / Polaris 12 admin. Called **backend** below.
- `payment-customization-js/` — Shopify extensions repo. Called **extensions repo** below.

---

## 0. Conventions and verified facts about the existing code

### 0.1 Global conventions

| Topic | Rule |
| --- | --- |
| Ruby namespace | Everything new lives in module `CodForm` (models `app/models/cod_form/*.rb`, services `app/services/cod_form/**`). There is **no** class named `CodForm`; do not create `app/models/cod_form.rb`. |
| Model tables | Namespaced models set `self.table_name` explicitly (table names in section B). |
| Engines | Pure Ruby under `app/services/cod_form/engine/` (module `CodForm::Engine`). Only stdlib (`json`, `bigdecimal`, `openssl`, `base64`, `date`, `time`, `set`, `digest`). No ActiveSupport methods (`blank?`, `present?`, `presence`, `try`, `to_json` on arbitrary objects are forbidden). Every file starts with the `require`/`require_relative` lines it needs, so `ruby -Itest test/services/cod_form/engine/x_test.rb` works outside Rails. |
| Engine hashes | **String keys only**, in and out. Adapters call `.deep_stringify_keys` / `as_json` before handing data to an engine. |
| Money | Every amount crossing an API or engine boundary is an **integer, amount × 100, in the buyer's presentment currency** (the same convention as Shopify's `/cart.js`, also for zero-decimal currencies). Field names end in `_cents`. Conversion to Shopify decimals (`cents / 100.0`, formatted with 2 decimals) happens only in `CodForm::Engine::DraftOrderBuilder`. Percentages are numbers `0..100`. |
| IDs | Shopify IDs are **strings of the numeric id** (no `gid://`) in all JSON. Our own record ids are integers. Session id is a UUID string (`public_id`). |
| JSON casing | `snake_case` everywhere: storefront API, admin API, metafield, DB JSON. The admin screens for this module must **not** use `Services/Api.js` (it runs `humps` on every key, which corrupts map keys such as country codes and text keys); they use `Pages/CodForm/api.js` (section H.3). |
| Time | ISO 8601 UTC strings in JSON; `datetime` columns in DB. |
| Feature keys | `snake_case` strings from the table in section J.1. |
| Order tags | `codking_form` (all form orders), `codking_form_test` (test orders: real orders the merchant cancels; they send messages like real orders but do not count toward the cap, velocity limits or analytics), `codking_form_partial` (partial orders that started in the form), `codking_abandoned_form` (abandoned-form draft orders), `codking_upsell` (order edited by upsell). |
| Note attribute names | `_codkFormSessionId`, `_codkFormId`, `_codkCodFee`, `_codkFormTest`, plus the existing `_otpVerifiedPhoneNumber`, `_codkSessionId`, `_codkCountryCode`, `_codk_campaign_json`. |

### 0.2 Verified facts (integration points)

All line numbers refer to the mirror at the date above.

| # | Fact | Where |
| --- | --- | --- |
| F1 | `POST /api/cod_orders` → `Api::CodOrdersController#create` → `ShopifyServices::CodOrderCreateService.call(shop, cart_data, shipping_address, buyer_identity, cod_fee, shipping_line_handle, otp_verified, meta_click_data:, client_context:, campaign_attribution:)`. Public, no token, no throttle beyond the global `req/ip` rule. | `app/controllers/api/cod_orders_controller.rb:6-88`, `config/routes.rb:383` |
| F2 | The service creates a draft order by GraphQL `draftOrderCreate`, then completes it by REST `ShopifyAPI::DraftOrder#complete(payment_pending: true)`, then `ShopifyAPI::Order.find`. | `app/services/shopify_services/cod_order_create_service.rb:33-83, 198-252, 418-435` |
| F3 | **Bug in existing code:** the 6th positional argument is stored as `@shipping_line_handle` (line 13) but `build_shipping_line` reads `@shipping_rate_details` (lines 341-364), which is never assigned. Shipping sent by the Express client is silently dropped; only `cod_fee` reaches the shipping line. | same file |
| F4 | In the Express path the COD fee is not a line: it is added to the shipping line amount and the title becomes `"<shipping title> + COD Fee"`. | same file `:366-391` |
| F5 | For **checkout** orders the COD fee is added after the order exists: `OrderConfirmationCreateJob#create_order` calls `ShopifyServices::CodFeesService`, which adds a "COD-Fees" product variant by order edit (`OrderEditService`, staff note `COD-Fees`). Percentage fee = `((cod_fees × total_price / 100) × 2).round / 2.0` (rounded to 0.5). | `app/workers/order_confirmation_create_job.rb:379-382, 587-593`, `app/services/shopify_services/cod_fees_service.rb`, `order_edit_service.rb` |
| F6 | PII in logs: `Rails.logger.info "Creating COD draft order with variables: #{variables.inspect}"` and the response dump; one Slack post per order for Meta success **and** failure. | `cod_order_create_service.rb:248-250, 114-140, 341-343, 359` |
| F7 | Confirmation / verification / fulfilment / COD-to-prepaid messaging is triggered by the Shopify `orders/create` webhook: `OrderConfirmationsController#create` → `NetworkJobs::WebhookForwarderJob` → `OrderConfirmationCreateJob#perform`. | `app/controllers/order_confirmations_controller.rb:694-697`, `app/workers/network_jobs/webhook_forwarder_job.rb:22-27` |
| F8 | That job has two branches. **Verified branch:** if the order has note attribute `_otpVerifiedPhoneNumber`, it saves a `COD-Verified` confirmation, links `PreOrderOtp` via `_codkSessionId` (= `PreOrderOtp.device_id`), and sends confirmation / first-purchase / prepaid messages. **Normal branch:** `create_order`. | `order_confirmation_create_job.rb:44-157, 200-222, 369-470` |
| F9 | In the normal branch, an order with `source_name == 'shopify_draft_order'` is set to `COD-SKIP-VERIFICATION` and the method **returns before any message is sent** when `setting.skip_draft_order` is true — and that column defaults to **true** (`db/schema.rb:1647`). When it is false, `CodFeesService` runs and would add the fee a second time to an order that already contains it. | `order_confirmation_create_job.rb:375-382` |
| F10 | COD detection: gateway names containing `cash`/`cod`/`bogus`/`manual`, or no gateway at all — a draft order completed with payment pending has none, so it counts as COD. | `app/services/order_confirmation_services/order_confirmation_post_service.rb:98-112`, `app/models/order_confirmation.rb:36` |
| F11 | Pre-order OTP endpoints the storefront calls today: `POST /order_confirmations/pre_order_otp` and `POST /order_confirmations/pre_order_otp_verify` (`config/routes.rb:666, 672`) → `NetworkServices::SendPreOrderOtpService.call(shop.id, params)` / `VerifyPreOrderOtpService.call(shop.id, params)`. Params (string keys): `country_code` (ISO2), `phone`, `mode` (`"WHATSAPP"` or anything else = SMS), `ip_address`, `device_id`, `cart_details`, `otp` (verify). Verify matches the newest `PreOrderOtp` with the same `device_id` **and** `phone` within 30 minutes. Send throttles on ip/device/phone (3 per minute, 10 per 5 min, 30 per day) and honours `Setting#pre_block_phone` and `Setting#locked`. | `app/controllers/order_confirmations_controller.rb:832-885`, `send_pre_order_otp_service.rb:52-149`, `verify_pre_order_otp_service.rb:6-98` |
| F12 | `PreOrderOtp` rows that carry `cart_details` and reach `order_status = 'AbandonedCheckout'` feed the abandoned-cart schedules. A wrapper that passes no `cart_details` stays out of that pipeline. | `app/workers/network_jobs/pre_order_otp_cart_schedule_job.rb:38-52` |
| F13 | Webhook-sourced abandoned carts use an **anchor** `AbandonedCart` row (`is_anchor: true`, `source`, `source_payload`, `checkout_id`, `url`) plus one stage row per offset in `Setting#ac_sms_schedule` / `ac_whatsapp_schedule`, each scheduled with `ShopifyJobs::AbandonedCartJob.perform_in`. BSP shops are picked up by `Whatsapp::ScheduleAbandonedCartRemindersJob` through `AbandonedCart.from_webhooks.anchors` (`WEBHOOK_SOURCES = %w[shopflo custom]`). `abandoned_carts.source` **already exists** (string, default `"shopify"`) — no migration needed for ABN-1. | `app/workers/webhooks/process_inbound_event_job.rb:70-217`, `app/models/abandoned_cart.rb:5-7`, `db/schema.rb` (`abandoned_carts`) |
| F14 | COD rules live on `Setting` as comma-separated strings and are enforced at checkout by the payment customization function. Exact semantics are in section E.3; the function matches postal codes by **exact string only**. | `payment-customization-js/extensions/cod-king-payment-customizaton-js/src/index.js:195-530` |
| F15 | `Setting` already has `cod_form_enabled` (boolean), `cod_form_v2` (boolean) and `cod_form_config` (jsonb). They belong to Express checkout and are shipped in `lightweight_settings`. **Do not read or write them for this module.** | `db/schema.rb` (`settings`), `app/models/setting.rb:16, 23, 372, 405` |
| F16 | Shop metafields are written with `ShopifyServices::MetafieldsSetService.call(shop, [{ownerId:, namespace: "codk", key:, value:, type:}])`; the owner id is `"gid://shopify/Shop/#{ShopifyAPI::Shop.current.id}"`. | `app/services/shopify_services/metafields_set_service.rb`, `app/models/setting.rb:558-600`, `app/models/shop.rb:412-451` |
| F17 | Partial rules: `PartialRuleSet` (see section E.11 for the fields used). Storefront reads them from `GET /order_confirmations/partial_rule_sets?shopifyDomain=&productId=` and from the `codk.partial_rule_sets` metafield (cart rules only). | `app/models/partial_rule_set.rb`, `order_confirmations_controller.rb:448-469` |
| F18 | RTO: `Rto::DecisionService.call(shopify_domain:, phone:, email:, zip:, country:, cart:)` → `{status:, cod_allowed:, band: "low"\|"medium"\|"high", risk_score: 0..100, probability:, reason_codes:, reasons:, ttl_seconds:}`. Cart value bands inside it assume INR. | `app/services/rto/decision_service.rb:27-90` |
| F19 | Funnel: `FormFunnelEvent` (`shop_id`, `session_token`, `event_type`, `occurred_at`, `metadata` jsonb), `EVENT_TYPES = %w[form_view checkout_initiated]`, ingest at `POST /form_funnel/ingest` (always 204). | `app/models/form_funnel_event.rb`, `app/controllers/form_funnel_controller.rb`, `config/routes.rb:511` |
| F20 | Meta CAPI purchase uses the deterministic event id `"order_#{order.id}_purchase"`. | `app/services/network_services/meta_conversion_service.rb:86-96` |
| F21 | The web pixel subscribes to the custom event `cod_order_placed` (`Shopify.analytics.publish`) with payload `{orderId, totalPrice, currencyCode, email, attribution}` and fires the Google Ads browser conversion plus an ingest POST. | `payment-customization-js/extensions/cod-king-web-pixel/src/index.js:419-440`, `cod-confirm/notifik-svelte-app/src/services/orderService.js:463-483` |
| F22 | `ShopDomain` is **not** a list of a shop's storefront domains. It is the RTO backfill registry keyed by the myshopify domain. The only storefront domain stored is `shops.primary_domain`. | `app/models/shop_domain.rb`, `db/schema.rb` (`shop_domains`, `shops`) |
| F23 | CORS allows every origin with credentials for GET/POST/DELETE/OPTIONS. Rack::Attack has one global throttle `req/ip` (40 per 5 s). `ShippingApi::OriginValidator` validates against an ENV list, not per shop. | `config/initializers/cors.rb`, `config/initializers/rack_attack.rb`, `app/services/shipping_api/origin_validator.rb` |
| F24 | Admin JSON endpoints authenticate with the App Bridge session token: controllers inherit `AuthenticatedController` (`before_action :set_shop`, `include ShopifyApp::Authenticated`), and the React app sends `Authorization: Bearer <shopify.idToken()>` plus `X-CSRF-Token`. | `app/controllers/authenticated_controller.rb`, `app/controllers/partial_rule_sets_controller.rb:1-2`, `app/javascript/packs/Services/Api.js:6-24` |
| F25 | Admin i18n for React is `config/localeJson/en.json` (imported by `app/javascript/packs/i18n-lang.js`; Crowdin source per `config/crowdin.yml:31-37`). `config/locales/en.yml` holds only server-side strings; it has no `settings_hub` section. | those files |
| F26 | Settings hub: `SETTINGS_GROUPS` / `SETTINGS_ITEMS` in `Pages/SettingsHub/registry.js`; `isVisible(ctx)` receives `{shop, setting, isPrepaidEnabled}` built in `SettingsHub.jsx:480-483`; `/features/*` is already a wrapped prefix (`registry.js:296-306`). Page routing is `renderRouteContent()` in `Pages/Home.jsx:251-390`; server routes for settings pages are the `settings_pages` lambda in `config/routes.rb:741-783`. | those files |
| F27 | Plan tier: `Sidekick::PlanCatalog.tier_for(shop)` → `"free" \| "pro" \| "enterprise" \| "enterprise_plus"` (`free` when `shop.charge_id` is blank). | `app/services/sidekick/plan_catalog.rb:14, 67-76` |
| F28 | Shop time zone: `ScheduledShopReport.extract_iana_from_shop_timezone(shop.owner_timezone)` returns an IANA name or `"UTC"`. | `app/models/scheduled_shop_report.rb:108-112` |
| F29 | Internal admin is Administrate behind one shared HTTP basic login (`ENV['ADMIN_USER']`). There is no per-person identity for audit. | `app/controllers/admin/application_controller.rb` |
| F30 | The existing embed block schema uses `"javascript": "script.js"`, which Shopify loads whenever the block is on. The Express embed intercepts Buy now / checkout clicks whenever `enable_pre_order_otp` or `partial_payment_enabled` is true (`app-embed.liquid:586-598, 634-700`). It has no "COD Form mode" off switch. | `payment-customization-js/extensions/cod-king-otp-extension/blocks/app-embed.liquid` |
| F31 | App scopes include draft orders, order edits, customers, products, discounts, themes, pixels. They do **not** include `read_shipping`. API version `2025-07`. | `config/initializers/shopify_app.rb:4-64` |
| F32 | Privacy webhooks are a stub: `ScriptController#delete_data` renders `{ok: true}`. | `app/controllers/script_controller.rb:200-204` |
| F33 | Today's partial flow from the storefront: cart attributes + `cartBuyerIdentityUpdate` (Storefront API, `Setting#store_front_token`) + redirect to `/checkout`, where the cart transform and discount functions do the rest. Exact steps in section G.9. | `notifik-svelte-app/src/utils/partialPaymentUtils.js`, `utils/bundlePaymentUtils.js:443-538`, `services/cartService.js:271-394`, `services/redirectOtpStoreToCheckoutService.js`, `services/callPartialDummyVariantId.js` |
| F35 | The backend uses `shopify_api` 9.5.2: GraphQL goes through `ShopifyAPI::GraphQL.client` and `client.parse`, which validates every query against the schema dumped for API version `2025-07` (`db/shopify_graphql_schemas/`, not present in the mirror). Every new field used in section F (`presentmentCurrencyCode`, `purchasingEntity`, `originalUnitPriceWithCurrency`, `contextualPricing`, `totalPriceSet`, `orderEditAddLineItemDiscount`, `codeDiscountNodeByCode`) must be checked against that dump on a real environment; they cannot be verified here. | `Gemfile.lock`, `app/services/shopify_services/*.rb` |
| F34 | The discount function applies whatever is in the cart attribute `_codkDiscounts` (`"<variantId>:<amount>\|<title>,orderLevel:<amount>\|<title>"`). | `payment-customization-js/extensions/cod-king-discount-function/src/run.graphql` |

---

## A. Components and main flow

### A.1 Components

```
Storefront page (theme)
 ├─ blocks/cod-form-embed.liquid ........ reads shop.metafields.codk.cod_form; emits nothing unless enabled
 │    ├─ inline <style> + slot script ... reserves the button slot (NFR-2)
 │    ├─ inline JSON config .............. window.__CODKF__
 │    └─ <script defer codk-form-loader.js>  (plain JS, IIFE)
 │         ├─ COD button / sticky / cart + drawer buttons, Buy now rename, hide toggles
 │         ├─ public API: window.CODKing.openForm(), .codking-open-form
 │         └─ on intent: import(codk-form-core.js)          (Preact, ESM)
 │              ├─ lazy chunks: otp, payment-option, handoff, qty-offer, bumps, downsell,
 │              │               upsell, discount, custom-fields, content-blocks, india,
 │              │               autocomplete, threshold, pixels-*, i18n-<locale>
 │              └─ calls /api/form/*
 │
Rails (cod-confirm)
 ├─ Api::Form::* controllers ............. token, origin, idempotency, throttles
 │    └─ CodForm::* services (AR adapters) → CodForm::Engine::* (pure Ruby)
 │         ├─ CodForm::CatalogService ......... variant prices/collections from Shopify (cached)
 │         ├─ CodForm::QuoteService ........... builds engine input, optional tax via DraftOrderCalculateService
 │         ├─ CodForm::OrderService ........... idempotent submit → ShopifyServices::CodOrderCreateService(form_context:)
 │         ├─ CodForm::OtpService ............. wraps Send/VerifyPreOrderOtpService
 │         └─ CodForm::Tracking::* / Integrations::* / AbandonmentService
 ├─ CodFormAdmin::* controllers .......... embedded-app JSON API (session-token auth)
 ├─ Admin::CodForm::* (Administrate) ..... plan limits, country groups, feature gates, global settings
 └─ React admin: Pages/CodForm/* ......... Setup, Buttons, Designer, Shipping, Fraud, Offers, Analytics tab
```

### A.2 Main sequence

```
Buyer                Loader/Form (browser)                    Rails                                Shopify
 │ tap COD button ─────►│                                        │                                    │
 │                      │ (core + i18n chunk already prefetched on touchstart/hover)                  │
 │                      │ POST /api/form/session ───────────────►│ verify origin, mode, gates, cap     │
 │                      │                                        │ pick form (targeting), CatalogService ──► nodes(ids) (cached 60 s)
 │                      │◄── token, form config, texts, schema,  │ Engine::Quote (no address yet)      │
 │                      │    offers, initial quote, cap state    │ create cod_form_sessions row        │
 │  form visible (one round trip, NFR-3)                         │                                    │
 │ edits qty/address/…─►│ POST /api/form/quote (debounced 250 ms)►│ Engine::Quote; tax only if needed ─────► draftOrderCalculate (cached)
 │ leaves phone field ─►│ POST /api/form/contact ───────────────►│ save contact on session             │
 │ submit ─────────────►│ client validation                      │                                    │
 │                      │ if otp.required:                       │                                    │
 │                      │   POST /api/form/otp/send ────────────►│ CodForm::OtpService → SendPreOrderOtpService
 │ enters code ────────►│   POST /api/form/otp/verify ──────────►│ → VerifyPreOrderOtpService; session.otp_verified_at
 │                      │ if quote.payment_options present:      │                                    │
 │ picks option ───────►│   partial/prepaid → POST /api/form/handoff, set cart attrs + buyer identity, go to /checkout  (END)
 │                      │   full COD ↓                           │                                    │
 │                      │ POST /api/form/orders ────────────────►│ compare-and-set session → re-quote  │
 │                      │                                        │ fraud + rules + cap re-check        │
 │                      │                                        │ CodOrderCreateService(form_context) ────► draftOrderCreate, complete
 │                      │                                        │ usage += 1, events, pixels (async)  │
 │                      │◄── order, thank_you, upsell?, event ids│                                    │──► orders/create webhook
 │                      │ browser pixels (Purchase, shared id)   │ OrderConfirmationCreateJob (existing messaging)
 │ upsell accept ──────►│ POST /api/form/upsell_accept ─────────►│ CodForm::UpsellService → order edit ───► orderEditBegin/AddVariant/Commit
 │                      │ thank-you (status page | URL | message | WhatsApp)
```

### A.3 Fallback rules (button is never dead — BTN rules, NFR-5, CAP-7)

"Fallback" always means **Shopify checkout**: on a product page `POST /cart/add.js` with the selected variant, quantity and properties, then `location.assign(root + 'checkout')`; on cart / drawer `location.assign(root + 'checkout')`. Implemented once in `src/shared/fallback.js#goToCheckout(ctx)`.

| Situation | Detected by | Behaviour |
| --- | --- | --- |
| COD Form mode off, module off, country not enabled, product excluded or failing a page-load COD rule | Liquid | Embed prints nothing. No script, no CSS. |
| Metafield says `cap_fallback: true` | loader | Button rendered; tap goes straight to checkout, no session call. |
| Core bundle fails to load within 6 s, or throws while mounting | loader | `goToCheckout` + `cf_fallback` event (`reason: "bundle"`). |
| Session call fails (network, 5xx, timeout 8 s) | core | `goToCheckout`, reason `session`. |
| Session returns `fallback` (`kill_switch`, `module_disabled`, `cap_reached`, `config_error`, `not_eligible_country`, `bundle_cart`) | core | `goToCheckout`, reason = code. |
| Buyer blocked later (block list, limit, postal rule, RTO high) | quote / orders | Stay in form: merchant message + "Pay online" button → prepaid hand-off (section G.9). |
| No qualifying shipping rate | quote | Submit disabled, merchant message (SHP-4). No redirect. |
| Order creation fails | orders | Form state kept, buyer message, retry allowed with the same idempotency key (ORD-7). |
| Global kill switch flipped | `cod_form_global_settings.kill_switch` | Session returns `fallback: "kill_switch"` immediately (effective on the next tap). `CodForm::MetafieldSyncAllJob` then rewrites every shop's metafield to `enabled: false`. |

---

## B. Database

### B.0 Migration rules

- One migration file per table, class `ActiveRecord::Migration[7.2]`, timestamps `20261003100100` … `20261003101800` in the order below.
- `create_table :x, if_not_exists: true do |t| … end`, every index as a separate `add_index …, if_not_exists: true` after the block (so a re-run after a partial failure is a no-op). No foreign-key constraints (the codebase does not use them for `shop_id`); `shop_id` is `bigint, null: false` with an index.
- **No existing table is altered.** `settings`, `abandoned_carts`, `form_funnel_events`, `order_confirmations`, `shops` keep their columns (F13: `abandoned_carts.source` already exists).
- jsonb columns: `null: false, default: {}` (or `[]`).
- Seed data (feature gates, plan limits, launch-market country group, global settings row) is inserted by `db/migrate/20261003101900_seed_cod_form_defaults.rb` with `insert_all(..., unique_by:)` / `find_or_create_by`, so it is idempotent.

### B.1 `cod_form_shop_configs` — `CodForm::ShopConfig` (`app/models/cod_form/shop_config.rb`)

One row per shop; created lazily by `CodForm::ShopConfig.for(shop)` (`find_or_create_by!(shop_id:)`). This table replaces the "one new field on settings" of the spec (decision 3).

| Column | Type | Null / default | Notes |
| --- | --- | --- | --- |
| `shop_id` | bigint | not null | unique index |
| `storefront_mode` | string | not null, `"legacy"` | `"legacy"` (whatever the shop does today: Shopify checkout rules and/or Express) or `"cod_form"`. The Setup screen displays "Shopify checkout" / "Express checkout" for `legacy` by deriving it from `Setting` (Express if `enable_pre_order_otp` or `partial_payment_enabled`); nothing on `Setting` is changed by a mode switch. |
| `module_access` | string | not null, `"default"` | `"default"` (follow `cod_form_global_settings.module_default_on`), `"on"`, `"off"` — the per-shop flag of NFR-12. |
| `enabled_at` | datetime | null | first time mode became `cod_form` |
| `general` | jsonb | not null, `{}` | shape B.1.1 |
| `fraud` | jsonb | not null, `{}` | shape B.1.2 |
| `setup_state` | jsonb | not null, `{}` | `{"embed_seen_at":…, "preset_chosen_at":…, "shipping_rate_added_at":…, "test_order_at":…, "dismissed_optin_at":…}` (DSH-6) |
| `feature_overrides` | jsonb | not null, `{}` | `{"<feature_key>": true\|false}` — per-shop gate override, internal admin only |
| `allowed_origins` | jsonb | not null, `[]` | extra storefront hosts, e.g. `["www.brand.com","brand.hu"]`; refreshed from Shopify `shop.domains` by `CodForm::DomainSyncJob` |
| `preview_token` | string | null | random 32 hex; FRD-5 |
| `config_version` | integer | not null, `0` | bumped by every admin write that affects the storefront |
| `metafield_synced_version` | integer | not null, `0` | |
| `metafield_synced_at` | datetime | null | |
| `asset_base` | string | null | last extension asset base URL reported by the storefront, only accepted when it starts with `https://cdn.shopify.com/extensions/#{ENV['COD_FORM_EXTENSION_UUID']}/` |
| `created_at`, `updated_at` | datetime | not null | |

Indexes: `index_cod_form_shop_configs_on_shop_id` (unique), `index_cod_form_shop_configs_on_storefront_mode`.

**B.1.1 `general`**

```json
{
  "countries": ["HU", "CO"],
  "pages": {"product": true, "cart": true, "drawer": true, "quick_buy": false},
  "products": {"scope": "all", "include_product_ids": [], "include_collection_ids": [], "exclude_product_ids": [], "exclude_collection_ids": []},
  "order_total": {"min_cents": null, "max_cents": null, "message": ""},
  "hide_out_of_stock": true,
  "cod_only_through_form": false,
  "cod_fee_taxable": false,
  "otp": {"mode": "before_order", "risk_band": "medium"},
  "rto": {"gating_enabled": false, "block_band": "high", "min_score": null, "message": ""},
  "discounts": {"code_field_enabled": false, "codes_combine_with_offers": false},
  "prepaid": {"show_pay_online": true, "discount_label_enabled": false},
  "consent": {"respect_customer_privacy": true},
  "branding": {"hide_powered_by": false},
  "autocomplete": {"enabled": false, "google_api_key": ""},
  "abandonment": {"enabled": true, "delay_minutes": 15, "create_draft_order": false, "recovery_discount": {"type": null, "value": 0}},
  "embedded": {"enabled": false, "selector": "", "position": "after", "form_id": null},
  "upsell_window_minutes": 5
}
```

`countries: []` means all countries. `products.scope` is `"all"` or `"selected"`. `otp.mode`: `"before_order"` (default, OTP-1), `"order_first"` (OTP-6), `"risk_based"` (OTP-7). The shop's OTP on/off, channel and templates are **not** stored here: they are read from `Setting` (`enable_pre_order_otp`, `max_retries`, `otp_wait_time`, `pre_whatsapp_button`).

**B.1.2 `fraud`**

```json
{
  "blocked_message": "",
  "limits": {
    "phone": {"enabled": false, "max_orders": 3, "window_hours": 24},
    "email": {"enabled": false, "max_orders": 3, "window_hours": 24},
    "ip":    {"enabled": false, "max_orders": 5, "window_hours": 24}
  },
  "limit_message": "",
  "max_quantity_per_order": null,
  "max_quantity_message": "",
  "min_submit_seconds": 3,
  "honeypot": true
}
```

### B.2 `cod_forms` — `CodForm::Form` (`app/models/cod_form/form.rb`)

| Column | Type | Null / default | Notes |
| --- | --- | --- | --- |
| `shop_id` | bigint | not null | |
| `name` | string | not null, `"Default form"` | |
| `is_default` | boolean | not null, `false` | exactly one per shop (enforced in model + partial unique index) |
| `status` | string | not null, `"active"` | `active`, `archived` |
| `position` | integer | not null, `0` | targeting priority, lower first |
| `targeting` | jsonb | not null, `{}` | `{"product_ids": [], "collection_ids": []}`; ignored for the default form |
| `template_key` | string | null | `classic`, `minimal`, `bold`, `compact` (FRM-21) |
| `draft_config` | jsonb | not null, `{}` | section C.2 |
| `published_config` | jsonb | not null, `{}` | section C.2; the storefront reads only this |
| `published_version` | integer | not null, `0` | |
| `published_at` | datetime | null | |
| `created_at`, `updated_at` | datetime | not null | |

Indexes: `(shop_id, status, position)`; unique partial `index_cod_forms_one_default` on `(shop_id)` `where: "is_default"`.
Limit: 5 non-archived forms per shop (FRM-22), validated in the model; the admin API allows only 1 without the gate `multiple_forms`.

### B.3 `cod_button_configs` — `CodForm::ButtonConfig` (`app/models/cod_form/button_config.rb`)

| Column | Type | Null / default | Notes |
| --- | --- | --- | --- |
| `shop_id` | bigint | not null | unique index |
| `preset` | string | not null, `"B"` | `A`, `B`, `C` |
| `config` | jsonb | not null, `{}` | section C.1.2 (`button`, `sticky`, `cart`, `theme`, `quantity_widget`) |
| `created_at`, `updated_at` | datetime | not null | |

Visibility rules are **not** here: the Setup screen owns them in `cod_form_shop_configs.general` (one screen ↔ one record).

### B.4 `cod_shipping_rates` — `CodForm::ShippingRate` (`app/models/cod_form/shipping_rate.rb`)

| Column | Type | Null / default | Notes |
| --- | --- | --- | --- |
| `shop_id` | bigint | not null | |
| `name` | string | not null | shown to buyer and used as the Shopify shipping line title |
| `description` | string | null | |
| `price_cents` | bigint | not null, `0` | in `currency`; `0` = free shipping (SHP-3) |
| `currency` | string | null | ISO 4217; null = shop currency. A rate applies only when it matches the quote currency (PRE-5); see E.5 |
| `conditions` | jsonb | not null, `{}` | section C.3 |
| `position` | integer | not null, `0` | |
| `active` | boolean | not null, `true` | |
| `source` | string | not null, `"manual"` | `manual`, `csv` (SHP-7 Shopify import is not built: no `read_shipping` scope is added) |
| `created_at`, `updated_at` | datetime | not null | |

Index: `(shop_id, active, position)`.

### B.5 `cod_offers` — `CodForm::Offer` (`app/models/cod_form/offer.rb`)

| Column | Type | Null / default | Notes |
| --- | --- | --- | --- |
| `shop_id` | bigint | not null | |
| `offer_type` | string | not null | `quantity`, `bump`, `upsell`, `downsell`, `threshold` |
| `name` | string | not null | internal name |
| `status` | string | not null, `"draft"` | `draft`, `active`, `paused`, `archived` |
| `priority` | integer | not null, `0` | lower first |
| `targeting` | jsonb | not null, `{}` | `{"scope": "all"\|"selected", "product_ids": [], "collection_ids": []}` |
| `config` | jsonb | not null, `{}` | section C.4, per type |
| `ab_test_id` | bigint | null | set while the offer is a variant of a running test |
| `starts_at`, `ends_at` | datetime | null | |
| `created_at`, `updated_at` | datetime | not null | |

Indexes: `(shop_id, offer_type, status, priority)`, `(ab_test_id)`.
Limits (validated on activation): 50 active quantity offers, 20 active bumps (at most 3 are shown in a form — the first three by `priority`), 1 active downsell, per shop. OFF-2 overlap check (a product in at most one active quantity offer) is `CodForm::Engine::OfferOverlap.conflicts(offers)`, called from the model validation for `product_ids`; overlap through collections is reported as a warning by the admin API, not rejected (membership is not known without Shopify calls).

### B.6 `cod_offer_ab_tests` — `CodForm::AbTest` (`app/models/cod_form/ab_test.rb`)

| Column | Type | Null / default | Notes |
| --- | --- | --- | --- |
| `shop_id` | bigint | not null | |
| `name` | string | not null | |
| `offer_type` | string | not null | all variants share it |
| `status` | string | not null, `"draft"` | `draft`, `running`, `stopped` |
| `variants` | jsonb | not null, `[]` | `[{"key": "a", "offer_id": 12, "weight": 50}, {"key": "control", "offer_id": null, "weight": 50}]`, 2–4 entries, weights sum to 100. `offer_id: null` = show nothing |
| `started_at`, `stopped_at` | datetime | null | variants are immutable once `started_at` is set (OFF-12) |
| `winner_key` | string | null | |
| `created_at`, `updated_at` | datetime | not null | |

Index: `(shop_id, status)`.

### B.7 `cod_block_entries` — `CodForm::BlockEntry` (`app/models/cod_form/block_entry.rb`)

| Column | Type | Null / default | Notes |
| --- | --- | --- | --- |
| `shop_id` | bigint | not null | |
| `kind` | string | not null | `phone`, `email`, `ip` |
| `value` | string | not null | as entered |
| `value_normalized` | string | not null | phone: digits only, no leading zeros; email: lower-case trimmed; ip: as is, or CIDR `a.b.c.d/nn` |
| `note` | string | null | |
| `created_by` | string | null | merchant email or `"import"` |
| `created_at`, `updated_at` | datetime | not null | |

Index: unique `(shop_id, kind, value_normalized)`. Limit: 5 000 entries per kind per shop.

### B.8 `cod_form_sessions` — `CodForm::Session` (`app/models/cod_form/session.rb`)

| Column | Type | Null / default | Notes |
| --- | --- | --- | --- |
| `shop_id` | bigint | not null | |
| `public_id` | string | not null | UUID v4; the `sid` in the token; unique |
| `cod_form_id` | bigint | null | |
| `form_version` | integer | null | `published_version` served |
| `status` | string | not null, `"open"` | `open`, `otp_pending`, `ordering`, `ordered`, `handoff_partial`, `handoff_prepaid`, `blocked`, `abandoned`, `recovered`, `expired` |
| `source` | string | not null, `"product"` | `product`, `cart`, `drawer`, `quick_buy`, `api`, `embedded`, `recovery` |
| `is_test` | boolean | not null, `false` | preview token used |
| `country_code`, `currency`, `locale`, `device` | string | null | device: `mobile`, `tablet`, `desktop` |
| `ip`, `user_agent` | string | null | |
| `client_id` | string | null | first-party id from localStorage (`codkf_cid`) |
| `cart_snapshot` | jsonb | not null, `{}` | last items sent: `{"items": [{"variant_id","quantity","properties"}], "source": …}` |
| `quote_snapshot` | jsonb | not null, `{}` | last server quote (section D.2 response `quote`) |
| `contact` | jsonb | not null, `{}` | `{"phone_e164","phone_national","email","first_name","last_name"}` |
| `phone_normalized`, `email_normalized` | string | null | for velocity limits and block lists |
| `address` | jsonb | not null, `{}` | |
| `custom_fields` | jsonb | not null, `{}` | |
| `attribution` | jsonb | not null, `{}` | keys of `CampaignAttributionHelper::ALLOWED_KEYS` plus `ttclid`, `sccid`, `epik` |
| `tracking` | jsonb | not null, `{}` | `{"fbp","fbc","ttp","ga_client_id","page_url","consent": {...}}` |
| `ab_assignments` | jsonb | not null, `{}` | `{"<ab_test_id>": "<variant key>"}` |
| `otp` | jsonb | not null, `{}` | `{"sends": 0, "failed_verifies": 0, "channel": "sms", "last_sent_at": …}` |
| `otp_verified_at` | datetime | null | |
| `risk` | jsonb | not null, `{}` | last RTO decision `{"band","score","checked_at"}` |
| `idempotency_key` | string | null | |
| `order_id` | string | null | Shopify order id |
| `order_name` | string | null | |
| `order_total_cents` | bigint | null | |
| `ordered_at` | datetime | null | |
| `order_error` | string | null | last failure code |
| `partial_rule_set_id` | bigint | null | chosen at the payment option step |
| `upsell` | jsonb | not null, `{}` | `{"offer_id","expires_at","accepted_at","declined_at","line_added": false}` |
| `closes_count` | integer | not null, `0` | |
| `downsell_offer_id` | bigint | null | accepted downsell |
| `recovery_token` | string | null | random 24 url-safe chars, set when abandoned |
| `abandoned_at`, `recovered_at` | datetime | null | |
| `abandoned_cart_id` | bigint | null | anchor row in `abandoned_carts` |
| `expires_at` | datetime | not null | token expiry (created + 2 h) |
| `created_at`, `updated_at` | datetime | not null | |

Indexes: unique `(public_id)`; `(shop_id, created_at)`; `(shop_id, status, updated_at)`; `(shop_id, order_id)`; unique partial `(shop_id, idempotency_key)` `where: "idempotency_key IS NOT NULL"`; `(shop_id, phone_normalized, ordered_at)` `where: "order_id IS NOT NULL"`; same for `email_normalized` and `ip`; unique partial `(recovery_token)` `where: "recovery_token IS NOT NULL"`.
Retention: `CodForm::SessionPurgeJob` (daily) deletes rows older than 90 days and blanks `contact`, `address`, `ip` on `ordered` rows older than 30 days.

### B.9 `cod_form_rejections` — `CodForm::Rejection` (`app/models/cod_form/rejection.rb`) — FRD-6

`shop_id` bigint not null · `session_public_id` string null · `reason_code` string not null (codes of E.9) · `stage` string not null (`session`, `quote`, `order`, `otp`) · `subject_kind` string null (`phone`, `email`, `ip`, `postal`, `product`, `bot`) · `subject_masked` string null (e.g. `+36•••••4521`, `a•••@x.com`) · `detail` jsonb not null `{}` · `ip` string null · `created_at` datetime not null (no `updated_at`).
Index: `(shop_id, created_at)`.

### B.10 `tracking_pixels` — `CodForm::TrackingPixel` (`app/models/cod_form/tracking_pixel.rb`)

| Column | Type | Null / default | Notes |
| --- | --- | --- | --- |
| `shop_id` | bigint | not null | |
| `platform` | string | not null | `meta`, `tiktok`, `ga4`, `google_ads`, `snapchat`, `pinterest` |
| `pixel_id` | string | not null | Meta pixel id / TikTok pixel code / GA4 measurement id / `AW-…` / Snap pixel id / Pinterest tag id |
| `access_token` | text | null | server API token (Meta CAPI, TikTok Events API, GA4 API secret, Snap CAPI, Pinterest). Stored like `settings.pixel_token` today (plain); never returned by any API (masked as `"••••1234"`) |
| `config` | jsonb | not null, `{}` | section C.6 |
| `targeting` | jsonb | not null, `{}` | `{"scope": "all"\|"selected", "product_ids": [], "collection_ids": []}` (TRK-8) |
| `enabled` | boolean | not null, `true` | |
| `position` | integer | not null, `0` | |
| `created_at`, `updated_at` | datetime | not null | |

Index: `(shop_id, platform, enabled)`; unique `(shop_id, platform, pixel_id)`. Limit: 5 pixels per platform per shop.
The existing single Meta pixel on `Setting` (`pixel_id`, `pixel_token`) keeps working unchanged; `CodForm::Tracking::PixelResolver` treats it as an implicit first Meta pixel when no `tracking_pixels` row with the same id exists.

### B.11 `form_order_usages` — `CodForm::OrderUsage` (`app/models/cod_form/order_usage.rb`)

`shop_id` bigint not null · `period` string not null (`"YYYY-MM"`, shop time zone) · `orders_count` integer not null `0` · `partial_orders_count` integer not null `0` · `test_orders_count` integer not null `0` · `over_cap_count` integer not null `0` · `overage_billed_count` integer not null `0` · `cap_snapshot` integer null (cap when it was first reached) · `notified_80_at`, `notified_100_at` datetime null · timestamps.
Index: unique `(shop_id, period)`.
Increment is a single statement (CAP-2): `INSERT … ON CONFLICT (shop_id, period) DO UPDATE SET orders_count = form_order_usages.orders_count + 1 RETURNING orders_count` in `CodForm::OrderUsage.increment!(shop_id:, period:, column: :orders_count)`.

### B.12 `plan_limits` — `CodForm::PlanLimit` (`app/models/cod_form/plan_limit.rb`)

| Column | Type | Null / default | Notes |
| --- | --- | --- | --- |
| `scope_type` | string | not null | `plan`, `country_group`, `shop` |
| `scope_key` | string | not null | plan tier (`free`, `pro`, `enterprise`, `enterprise_plus`) / `cod_form_country_groups.id` / `shops.id`, as string |
| `plan_tier` | string | null | only for `country_group` rows: restricts the override to one tier; null = all tiers |
| `monthly_cap` | integer | null | null = unlimited (CAP-3) |
| `at_cap_behaviour` | string | null | `fallback`, `grace`, `flag_only`; null = inherit the next level, finally `cod_form_global_settings.at_cap_behaviour` |
| `grace_orders` | integer | null | used with `grace` |
| `overage_rate` | decimal(10,4) | null | USD per extra order; null = not billed (CAP-9) |
| `active` | boolean | not null, `true` | |
| `note` | string | null | |
| `created_at`, `updated_at` | datetime | not null | |

Index: unique `(scope_type, scope_key, plan_tier)` (Postgres treats null as distinct, so the model also validates uniqueness for null `plan_tier`).

### B.13 `cod_form_country_groups` — `CodForm::CountryGroup` (`app/models/cod_form/country_group.rb`)

`name` string not null · `country_codes` jsonb not null `[]` (ISO2 upper-case) · `position` integer not null `0` (first matching group wins) · `active` boolean not null `true` · timestamps. Seed: `{"name": "Launch markets", "country_codes": ["HU","CO","RS","DO","MA","PE","PK"], "position": 0}` (CAP-4). The shop's country is `shops.country_code`.

### B.14 `feature_gates` — `CodForm::FeatureGate` (`app/models/cod_form/feature_gate.rb`)

`feature_key` string not null (unique) · `min_tier` string not null `"free"` · `enabled` boolean not null `true` (false = feature off for everyone) · `description` string null · timestamps. Seed in section J.1.

### B.15 `cod_form_global_settings` — `CodForm::GlobalSetting` (`app/models/cod_form/global_setting.rb`)

Singleton (`CodForm::GlobalSetting.current` = `first_or_create!`, cached 30 s in `Rails.cache` under `codf:global`).
`kill_switch` boolean not null `false` · `module_default_on` boolean not null `false` (flip to true at general release) · `at_cap_behaviour` string not null `"fallback"` · `grace_orders` integer not null `0` · `async_orders` boolean not null `false` (ORD-9) · `usage_notice_thresholds` jsonb not null `[80, 100]` · `settings` jsonb not null `{}` (rate-limit overrides, see D.0.4) · timestamps.

### B.16 `cod_form_admin_audits` — `CodForm::AdminAudit` (`app/models/cod_form/admin_audit.rb`) — CAP-5

`auditable_type` string not null · `auditable_id` bigint null · `action` string not null (`create`, `update`, `destroy`) · `changed_fields` jsonb not null `{}` (`{"monthly_cap": [50, 100]}`) · `actor` string null (see F29: `"admin:#{ENV['ADMIN_USER']}"`) · `ip` string null · `created_at` datetime not null.
Index: `(auditable_type, auditable_id, created_at)`. Written by the `CodForm::AdminAudited` concern (after-commit callbacks reading `CodForm::Current.actor` / `.ip`), included in `PlanLimit`, `CountryGroup`, `FeatureGate`, `GlobalSetting`, and `ShopConfig` (for `module_access` and `feature_overrides` only).

Merchant-side changes are written to the existing `settings_change_audits` table (DSH-14) by `CodForm::MerchantAudit.record(shop, field, old, new)` with `field` prefixed `cod_form.` (e.g. `cod_form.storefront_mode`, `cod_form.button.preset`, `cod_form.form.12.published`) and `changed_by: "merchant"`.

### B.17 `cod_form_daily_stats` — `CodForm::DailyStat` (`app/models/cod_form/daily_stat.rb`) — ANL-5

| Column | Type | Null / default |
| --- | --- | --- |
| `shop_id` | bigint | not null |
| `stat_date` | date | not null (shop time zone) |
| `dimension` | string | not null, `"all"` — `all`, `country`, `device`, `product`, `form`, `utm_campaign`, `offer` |
| `dimension_value` | string | not null, `""` |
| `metrics` | jsonb | not null, `{}` |
| timestamps | | |

`metrics` keys (integers unless noted): `button_views, form_opens, first_inputs, shipping_selected, submit_attempts, submit_errors, orders, revenue_cents, partial_handoffs, prepaid_redirects, closes, otp_sent, otp_verified, offer_views, offer_accepts, downsell_shown, downsell_accepts, upsell_views, upsell_accepts, recovery_opens, recovered_orders, blocked, fallbacks`. `revenue_cents` is in shop currency (presentment totals are converted with `ExchangeRateBank` when they differ).
Index: unique `(shop_id, stat_date, dimension, dimension_value)`.
Rollups support one dimension filter at a time; combined filters (country **and** device **and** product) are answered from raw `form_funnel_events` and are therefore limited to the last 90 days.

### B.18 `cod_form_integrations` — `CodForm::Integration` (`app/models/cod_form/integration.rb`)

`shop_id` bigint not null · `provider` string not null (`google_sheets`, `klaviyo`, `omnisend`, `rabbitpay`) · `status` string not null `"disconnected"` (`connected`, `error`) · `credentials` jsonb not null `{}` (never serialised to the admin API) · `config` jsonb not null `{}` · `last_error` string null · `last_success_at` datetime null · timestamps.
Index: unique `(shop_id, provider)`.
`google_sheets` → `credentials: {"refresh_token","access_token","expires_at","email"}`, `config: {"spreadsheet_id","sheet_name","columns": ["order_name","created_at","customer_name","phone", …]}`.
`klaviyo` → `credentials: {"private_api_key"}`, `config: {"events": {"order": true, "abandoned": true}}`. `omnisend` → `credentials: {"api_key"}`, same `config`.

### B.19 Existing models touched (code only, no schema change)

| File | Change | Owner |
| --- | --- | --- |
| `app/models/form_funnel_event.rb` | `EVENT_TYPES` gains the `cf_*` list of section I.1 | WS8 |
| `app/models/abandoned_cart.rb` | `WEBHOOK_SOURCES = %w[shopflo custom cod_form]` | WS8 |
| `app/models/shop.rb` | add `has_one :cod_form_shop_config, class_name: "CodForm::ShopConfig", dependent: :destroy` and `has_many` for forms, offers, shipping rates, block entries, sessions, pixels, usages, integrations (all `dependent: :delete_all`) | WS1 |

---

## C. Canonical config schemas

All shapes are produced and validated by pure classes in `CodForm::Engine` (section E.13): the admin API calls `normalize` on save, the storefront receives only normalized output. Unknown keys are dropped; missing keys are filled from defaults.

### C.1 The `codk.cod_form` shop metafield (type `json`)

Built by `CodForm::Engine::MetafieldPayload.build(input)` and written by `CodForm::MetafieldSyncService.call(shop)` (uses `ShopifyServices::MetafieldsSetService`, F16) whenever `config_version > metafield_synced_version`. The service is enqueued as `CodForm::MetafieldSyncJob.perform_async(shop_id)` from `CodForm::ShopConfig#bump_version!`, which every admin write calls. It is also re-run when a COD-rule or COD-fee column of `Setting` changes: a `Setting.after_commit` hook registered in `config/initializers/cod_form.rb` inside `Rails.application.config.to_prepare` (so `setting.rb` itself is not edited) enqueues the job when `saved_changes` touches one of the columns of E.3 / E.8.

Size rule: every id list in the payload is capped at 250 entries. When a list is longer the payload sets `"overflow": true` in that section and the loader skips that client-side check (the server still enforces it at session/quote).

#### C.1.1 Full example

```json
{
  "v": 37,
  "enabled": true,
  "api": "https://app.codking.tech",
  "shop": "brand.myshopify.com",
  "cap_fallback": false,
  "test_only": false,
  "countries": ["HU", "CO"],
  "pages": {"product": true, "cart": true, "drawer": true, "quick_buy": false},
  "vis": {
    "scope": "all",
    "inc_p": [], "inc_c": [], "exc_p": ["8123"], "exc_c": [],
    "min_cents": null, "max_cents": 5000000,
    "hide_oos": true,
    "overflow": false
  },
  "rules": {
    "hide_p": [], "show_p": [], "hide_v": [], "hide_c": [], "show_c": [],
    "hide_vendors": [], "show_vendors": [],
    "min_cents": null, "max_cents": null,
    "overflow": false
  },
  "button": {
    "preset": "B",
    "labels": {"default": "Buy with COD", "hu": "Fizetés utánvéttel"},
    "subtitles": {"default": ""},
    "style": {
      "bg": "#111111", "color": "#ffffff",
      "border_color": "#111111", "border_width": 0, "radius": 8,
      "shadow": "none", "font_size": 16, "bold": true, "height": 48, "full_width": true,
      "icon": "cash", "animation": "none"
    },
    "placement": {"position": "below", "selector": ""},
    "sticky": {"enabled": true, "labels": {"default": "Buy with COD"}},
    "cart": {"enabled": true, "labels": {"default": "Checkout with COD"}, "selector": ""},
    "drawer": {"enabled": true, "labels": {"default": "Checkout with COD"}, "selector": ""},
    "quick_buy": {"enabled": false, "selector": ""}
  },
  "theme": {
    "rename_buy_now": {"default": ""},
    "hide": {"add_to_cart": false, "buy_now": false, "checkout": false, "wallets": false}
  },
  "features": ["otp", "partial", "qty_offer", "pixels"],
  "qo": [
    {
      "id": 12, "p": ["8111", "8112"], "c": [], "all": false, "layout": "cards",
      "title": {"default": "Buy more, save more"},
      "tiers": [
        {"q": 1, "type": "none", "value": 0, "label": {"default": "1 pack"}, "badge": {"default": ""}, "image": "", "pre": false},
        {"q": 2, "type": "percentage", "value": 10, "label": {"default": "2 packs"}, "badge": {"default": "Most popular"}, "image": "", "pre": true},
        {"q": 3, "type": "unit_price", "value": 149900, "label": {"default": "3 packs"}, "badge": {"default": ""}, "image": "", "pre": false}
      ]
    }
  ],
  "embedded": {"enabled": false, "selector": "", "position": "after"},
  "prepaid_label": {"default": ""},
  "rtl_locales": ["ar", "ur", "he", "fa"],
  "preview": false
}
```

#### C.1.2 Field reference

| Key | Type | Meaning |
| --- | --- | --- |
| `v` | int | `cod_form_shop_configs.config_version`. Sent back in the session call (`v`) so the server can tell a stale page. |
| `enabled` | bool | `storefront_mode == "cod_form"` **and** module on for the shop **and** kill switch off **and** feature `cod_form_core` allowed. Liquid prints nothing when false. |
| `api` | string | API base, `"https://#{ENV['APP_HOST']}"`, no trailing slash. |
| `shop` | string | myshopify domain. |
| `cap_fallback` | bool | cap reached with behaviour `fallback` (CAP-7). |
| `test_only` | bool | true while the merchant has never switched the form live but is testing: the embed renders only when the URL has `?codk_preview=<preview_token>` (token is compared server-side, the loader only checks presence). |
| `countries` | string[] | VIS-3; `[]` = all. Compared in Liquid with `localization.country.iso_code`. |
| `pages` | object | VIS-1. |
| `vis` | object | VIS-2/4/5: `scope` (`all`/`selected`), include/exclude product and collection ids, order-total range (cents, shop currency), `hide_oos`. |
| `rules` | object | Page-load COD rules mirrored from `Setting` (VIS-6): `hide_p` = `selected_product_ids`, `show_p` = `show_product_ids`, `hide_v` = `hide_product_variant_ids`, `hide_c` = `excluded_collection_ids`, `show_c` = `selected_collection_ids`, `hide_vendors`, `show_vendors` (lower-cased), `min_cents`/`max_cents` from `min_cart_total`/`max_cart_total`. |
| `button.preset` | `"A"`/`"B"`/`"C"` | Section 3 of the spec. In `B` the loader ignores `theme.rename_buy_now`. In `A` no COD button is injected on the product page; the Buy now click opens the form. |
| `button.labels`, `subtitles`, all other `*labels` | `{locale: string}` | `default` is mandatory; the Liquid picks `request.locale.iso_code`, then its language part, then `default`. Labels support `{total}` (formatted money of variant price × quantity, or cart total) — BTN-6. |
| `button.style.shadow` | `none`/`sm`/`md`/`lg` | |
| `button.style.icon` | `none`/`cash`/`truck`/`cart`/`bolt` | inline SVG shipped in the loader. |
| `button.style.animation` | `none`/`pulse`/`shake` | |
| `button.placement.position` | `below`/`above`/`custom` | relative to the theme's buy buttons; with `custom`, `selector` is the anchor and the button is appended inside it (BTN-2). |
| `theme.rename_buy_now` | `{locale: string}` | BTN-8; empty = unchanged. |
| `theme.hide.*` | bool | BTN-9. |
| `features` | string[] | which optional chunks may be needed, so the loader can prefetch them on intent: `otp`, `partial`, `qty_offer`, `bumps`, `downsell`, `upsell`, `discount`, `custom_fields`, `content`, `india`, `autocomplete`, `threshold`, `pixels`, `embedded`, `preset_a`. |
| `qo` | array | Active quantity offers needed before the form opens (OFF-3). The Liquid emits **only the one offer that matches the current product** (by `p`, `c` or `all`). `tiers[].type`: `none`, `percentage`, `fixed_amount` (cents off the line), `unit_price` (cents per unit). `layout`: `cards`, `list`, `compact`. |
| `embedded` | object | FRM-20. |
| `prepaid_label` | `{locale: string}` | PRE-2: text appended to the renamed Buy now label, e.g. `"(5% off)"`. |
| `preview` | bool | set only in theme-editor renders. |

`cod_button_configs.config` stores exactly the keys `button` (without `preset`), `theme`, and `quantity_widget: {"enabled": true, "position": "above_buttons", "selector": ""}`. Default (`CodForm::Engine::Defaults.button_config`, the same for every shop and country): preset `B`; label "Buy with COD"; no subtitle; background `#111111`, text `#ffffff`; no animation; placement `below`; sticky mobile button on with the same label; cart and drawer buttons on with label "Checkout with COD"; quick-buy off; Buy now rename empty; no hide toggle on.

### C.2 Form config (`cod_forms.draft_config` / `published_config`)

```json
{
  "schema": 1,
  "mode": "popup",
  "design": {
    "primary": "#111111", "on_primary": "#ffffff", "text": "#1a1a1a", "muted": "#6b7280",
    "background": "#ffffff", "surface": "#f6f6f7", "border": "#d9d9de", "error": "#d72c0d",
    "radius": 10, "field_radius": 8, "density": "comfortable",
    "header": {"show_title": true, "logo_url": "", "show_close": true},
    "sticky_submit": true, "hide_shipping_selector_when_single": true
  },
  "blocks": [
    {"id": "order_summary", "type": "order_summary", "enabled": true, "settings": {"show_image": true, "show_compare_at": true, "show_quantity": true}},
    {"id": "quantity_offer", "type": "quantity_offer", "enabled": true, "settings": {}},
    {"id": "contact", "type": "fields", "enabled": true, "settings": {"group": "contact", "title_key": "contact_title"}},
    {"id": "address", "type": "fields", "enabled": true, "settings": {"group": "address", "title_key": "address_title"}},
    {"id": "shipping", "type": "shipping", "enabled": true, "settings": {}},
    {"id": "bumps", "type": "bumps", "enabled": true, "settings": {}},
    {"id": "discount", "type": "discount", "enabled": false, "settings": {}},
    {"id": "totals", "type": "totals", "enabled": true, "settings": {"show_tax_line": false}},
    {"id": "submit", "type": "submit", "enabled": true, "settings": {"show_total_in_button": true}}
  ],
  "fields": [
    {"key": "first_name", "type": "text", "group": "contact", "enabled": true, "required": true, "width": "half", "autocomplete": "given-name", "validation": {"max": 60}},
    {"key": "last_name", "type": "text", "group": "contact", "enabled": true, "required": false, "width": "half", "autocomplete": "family-name", "validation": {"max": 60}},
    {"key": "phone", "type": "tel", "group": "contact", "enabled": true, "required": true, "width": "full", "autocomplete": "tel-national", "validation": {}},
    {"key": "email", "type": "email", "group": "contact", "enabled": false, "required": false, "width": "full", "autocomplete": "email", "validation": {}},
    {"key": "country", "type": "country", "group": "address", "enabled": true, "required": true, "width": "full", "validation": {}},
    {"key": "address1", "type": "text", "group": "address", "enabled": true, "required": true, "width": "full", "autocomplete": "address-line1", "validation": {"min": 3, "max": 120}},
    {"key": "address2", "type": "text", "group": "address", "enabled": false, "required": false, "width": "full", "autocomplete": "address-line2", "validation": {"max": 120}},
    {"key": "province", "type": "province", "group": "address", "enabled": true, "required": true, "width": "half", "validation": {}},
    {"key": "city", "type": "city", "group": "address", "enabled": true, "required": true, "width": "half", "validation": {"max": 80}},
    {"key": "zip", "type": "postal", "group": "address", "enabled": true, "required": null, "width": "half", "autocomplete": "postal-code", "validation": {}},
    {"key": "gst_number", "type": "text", "group": "address", "enabled": false, "required": false, "width": "full", "only_countries": ["IN"], "validation": {"regex": "^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$"}},
    {"key": "note", "type": "textarea", "group": "address", "enabled": false, "required": false, "width": "full", "validation": {"max": 500}},
    {"key": "marketing_consent", "type": "consent", "group": "contact", "enabled": false, "required": false, "width": "full", "default_checked": false, "channels": ["sms", "email"]}
  ],
  "texts": {
    "en": {"title": "Cash on Delivery", "submit": "Complete order — {total}"},
    "hu": {"title": "Utánvétes rendelés"}
  },
  "thank_you": {
    "type": "order_status",
    "url": "",
    "message": {"en": "Thank you {first_name}! Your order {order_name} is confirmed."},
    "whatsapp": {"phone": "", "message": {"en": "Hi, I just placed order {order_name}."}}
  },
  "steps": {"phone_first": false},
  "pay_online": {"enabled": true}
}
```

Rules:

- The example above **is** the default form (`Defaults.form_config`): shown and required — first name, phone, address line 1, and city / province / postal code as the country schema says; shown and optional — last name; off — email, address line 2, note, GST number, marketing consent. The discount block is off.
- `schema` — integer; `CodForm::Engine::FormConfig.normalize` migrates older shapes.
- `mode` — `popup` (FRM-1) or `embedded` (FRM-20).
- `blocks` — ordered (FRM-2, FRM-12). `type` ∈ `order_summary`, `quantity_offer`, `fields`, `shipping`, `bumps`, `discount`, `totals`, `submit`, and the P2/P3 content types `rich_text` (`settings.html`, sanitised server-side to `b i u a br p ul ol li strong em span` with `href` https only), `image` (`settings.url`, `alt`, `link`), `trust_badges` (`settings.items: [{"icon","text"}]`), `countdown` (`settings.minutes`, `text_key`), `threshold_bar` (`settings.offer_id`). `id` is unique in the form; the eight core blocks keep the ids shown. Exactly one `submit` block, always last among enabled blocks.
- `fields` — ordered inside their `group`. `key` is one of the built-in keys above or `cf_<8 lowercase alnum>` for custom fields (FRM-13). `type` ∈ `text`, `tel`, `email`, `country`, `province`, `city`, `postal`, `textarea`, `consent`, and for custom fields `text`, `textarea`, `select`, `radio`, `checkbox`, `date` (with `options: [{"value","label": {locale: string}}]` for select/radio). `required: null` means "follow the country schema" (used for `zip`, `province`, `city`). `validation`: `min`, `max` (lengths), `regex` (FRM-15, max 200 chars, compiled with a 50 ms timeout guard), `latin_only` (bool). `phone` and `country` cannot be disabled; `country` is rendered only when more than one country is enabled.
- Labels, placeholders and error texts are **not** on the field: they are text keys (`label_<key>`, `placeholder_<key>`, `error_<key>`), so every string is editable per locale (FRM-3, FRM-10, FRM-19). Custom fields use the same key pattern.
- `texts` — merchant overrides only, `{locale: {text_key: string}}`. Defaults come from the storefront package (section G.7). Max 300 chars per string, max 12 locales.
- `thank_you.type` — `order_status` (default), `custom_url`, `message`, `whatsapp` (TY-1). When the type is `order_status` and the order has no status URL, the form shows the `message` type with the default text `thank_you_message`. Variables allowed in `url`, `message`, `whatsapp.message`: `{order_name} {order_number} {order_id} {total} {first_name} {last_name} {phone} {email}`; values are URL-encoded when substituted into a URL.
- `steps.phone_first` — FRM-18, default false.
- Publishing copies `draft_config` → `published_config` after `normalize` returns no errors, sets `published_at`, increments `published_version`, bumps the shop `config_version`.

Templates (FRM-21): `CodForm::Engine::Defaults.templates` returns `[{ "key", "name", "design": {...}, "blocks_order": [...] }]` for `classic`, `minimal`, `bold`, `compact`; applying a template replaces `design` and block order only.

### C.3 Shipping rate (`cod_shipping_rates`)

API representation (admin API and engine input):

```json
{
  "id": 4, "name": "Standard delivery", "description": "2–4 business days",
  "price_cents": 149000, "currency": "HUF", "position": 0, "active": true, "source": "manual",
  "conditions": {
    "countries": ["HU"],
    "provinces": ["HU-BU", "HU-PE"],
    "subtotal_min_cents": null, "subtotal_max_cents": 1999999,
    "weight_min_grams": null, "weight_max_grams": 20000,
    "quantity_min": null, "quantity_max": null,
    "products": {"mode": "any", "product_ids": [], "collection_ids": []}
  }
}
```

- All conditions are AND-ed; a null/empty condition is ignored (SHP-2).
- `provinces` holds `"<country>-<province code>"` strings.
- `subtotal_*` compares against the discounted merchandise subtotal (after offers, before shipping and fee), bounds inclusive.
- `products.mode` (SHP-6): `any` (no product condition), `only` (every cart line must match `product_ids`/`collection_ids`), `exclude` (no cart line may match).
- Free shipping = a rate with `price_cents: 0` and conditions (SHP-3).

### C.4 Offers (`cod_offers.config` per `offer_type`)

Common wrapper returned by the admin API: `{"id", "offer_type", "name", "status", "priority", "targeting", "config", "ab_test_id", "starts_at", "ends_at"}`.

**quantity** (OFF-1..4)

```json
{
  "title": {"default": "Buy more, save more"},
  "layout": "cards",
  "show_widget_on_product_page": true,
  "tiers": [
    {"quantity": 1, "discount_type": "none", "value": 0, "label": {"default": "1 pack"}, "badge": {"default": ""}, "image_url": "", "preselected": false},
    {"quantity": 2, "discount_type": "percentage", "value": 10, "label": {"default": "2 packs"}, "badge": {"default": "Most popular"}, "image_url": "", "preselected": true},
    {"quantity": 3, "discount_type": "unit_price", "value": 149900, "label": {"default": "3 packs"}, "badge": {"default": ""}, "image_url": "", "preselected": false}
  ],
  "apply_to_higher_quantities": true
}
```

`discount_type`: `none`, `percentage` (0–100), `fixed_amount` (cents off the whole line), `unit_price` (cents per unit). Tiers are sorted by `quantity`, 1–5 tiers, at most one `preselected`. A line with quantity `n` gets the tier with the largest `quantity ≤ n` when `apply_to_higher_quantities` is true, otherwise only an exact match.

**bump** (OFF-5, OFF-6)

```json
{
  "title": {"default": "Add express handling"},
  "description": {"default": "Ships tomorrow"},
  "image_url": "",
  "kind": "custom",
  "variant_id": null,
  "price_cents": 49900,
  "compare_at_cents": null,
  "checked_by_default": false,
  "quantity_picker": false, "max_quantity": 1,
  "requires_shipping": false, "taxable": true,
  "position": "before_totals"
}
```

`kind`: `variant` (then `variant_id` is required; price defaults to the variant's contextual price unless `price_cents` is set, in which case the difference is applied as a line discount) or `custom` (custom draft-order line). `position`: `after_summary`, `before_shipping`, `before_totals`.

**downsell** (OFF-7)

```json
{
  "trigger_after_closes": 1,
  "discount_type": "percentage", "value": 10,
  "title": {"default": "Wait! Here is 10% off"},
  "body": {"default": "Complete your order now and save."},
  "accept_label": {"default": "Claim discount"}, "decline_label": {"default": "No thanks"},
  "timer_seconds": 0
}
```

`discount_type`: `percentage` or `fixed_amount` (cents off the order's merchandise). Shown once per session. Default for a new downsell: first close, 10 % off, no timer; one active downsell per shop.

**upsell** (OFF-10)

```json
{
  "variant_id": "44123",
  "quantity": 1,
  "discount_type": "percentage", "value": 20,
  "title": {"default": "Add one more for 20% off"},
  "body": {"default": ""},
  "accept_label": {"default": "Add to my order"}, "decline_label": {"default": "No thanks"},
  "timer_seconds": 120
}
```

The accept window is `general.upsell_window_minutes` (default 5) from order creation; the on-screen timer defaults to 120 s. One upsell per order: the highest-priority active offer that matches the cart.

**threshold** (OFF-11)

```json
{
  "kind": "free_shipping",
  "threshold_cents": 1500000,
  "gift_variant_id": null,
  "text_progress": {"default": "Add {remaining} more for free shipping"},
  "text_reached": {"default": "You unlocked free shipping!"}
}
```

`kind`: `free_shipping` (when reached, every qualifying rate is priced 0) or `free_gift` (adds `gift_variant_id` × 1 at 100 % line discount).

### C.5 Block entry (`cod_block_entries`)

```json
{"id": 91, "kind": "phone", "value": "+36 30 123 4567", "value_normalized": "36301234567", "note": "refused 3 parcels", "created_by": "owner@brand.com", "created_at": "2026-10-03T09:12:00Z"}
```

Matching (`CodForm::Engine::Fraud`): `phone` — the entry's digits equal the buyer's full international digits, **or** equal the national number (so an entry without the dial code still matches); `email` — exact, or `*@domain.com` wildcard on the domain; `ip` — exact or CIDR.

### C.6 Pixel (`tracking_pixels`)

```json
{
  "id": 7, "platform": "tiktok", "pixel_id": "C4ABCDEF123", "access_token_masked": "••••9f2a", "enabled": true, "position": 0,
  "targeting": {"scope": "all", "product_ids": [], "collection_ids": []},
  "config": {
    "browser": true, "server": true,
    "purchase_event": "purchase",
    "events": {"form_open": true, "add_payment_info": false, "purchase": true},
    "test_event_code": "",
    "conversion_label": "",
    "ad_account_id": ""
  }
}
```

- `purchase_event`: `purchase` or `lead` (TRK-2: send Lead in place of Purchase). Platform event names are mapped in `CodForm::Tracking::EventMap` (section I.2).
- `conversion_label` — Google Ads only (`pixel_id` = `AW-123`, label = `AbC-D_efG`). `ad_account_id` — Pinterest only.
- Storefront representation (session response) drops the token: `{"platform","pixel_id","config": {"browser","purchase_event","events","conversion_label"}, "targeting"}`.

---

## D. HTTP API

### D.0 Storefront API — common rules

**D.0.1 Transport.** Base `cfg.api + "/api/form"`. Every call is `POST` (except the two geo `GET`s) with header `Content-Type: text/plain;charset=UTF-8` and a JSON string body. This keeps the request a CORS "simple request": **no preflight**, so opening the form is one round trip (NFR-3). The token travels in the body (`token`), never in a header. Every URL carries `?shop=<myshopify domain>` so Rack::Attack can key on the shop without parsing the body. Responses are `application/json`. `credentials: "omit"`.

**D.0.2 Base controller.** `Api::Form::BaseController < ActionController::API` (`app/controllers/api/form/base_controller.rb`):

```ruby
before_action :parse_body!        # @body = JSON.parse(request.raw_post) (Hash, string keys); 400 invalid_request on failure or > 64 KB
before_action :load_shop!         # Shop.find_by_shopify_domain_with_cache(params[:shop]); 404 shop_not_found
before_action :check_origin!      # CodForm::OriginGuard.allowed?(shop, shop_config, request) → 403 origin_not_allowed
before_action :check_module!      # CodForm::Availability.call(shop) → fallback payload (see below)
before_action :authenticate_session!, except: [...]   # token → @form_session; 401 invalid_token / token_expired
```

- `CodForm::OriginGuard`: takes the host of `Origin` (else `Referer`). Allowed hosts: `shop.shopify_domain`, host of `shop.primary_domain`, `shop_config.allowed_origins`, any `*.shopifypreview.com`, and `localhost` / `127.0.0.1` only when `Rails.env.development?` or `ENV["COD_FORM_ALLOW_LOCALHOST"] == "true"` (test harness). A missing `Origin` and `Referer` is rejected. `ENV["COD_FORM_ORIGIN_ENFORCE"] == "false"` turns rejection into a logged warning (roll-out switch). Note F22: do not use `ShopDomain`.
- Token: `CodForm::Engine::SessionToken` (E.12), secret `Rails.application.key_generator.generate_key("cod_form_session_v1", 32)`. `authenticate_session!` loads `CodForm::Session.find_by(shop_id:, public_id:)`, checks `expires_at`.
- The controller never logs the body. `config/initializers/filter_parameter_logging.rb` gains `:phone, :email, :address1, :address2, :first_name, :last_name, :zip, :token, :otp` (WS3 snippet).

**D.0.3 Error envelope** (all non-2xx, and 200 with `ok: false` is never used):

```json
{"ok": false, "error": {"code": "blocked", "message_key": "error_blocked", "message": "We cannot accept cash on delivery for this order.", "fallback": null, "fields": {}, "retry_after": null}}
```

`message` is the merchant's custom text when one is configured, otherwise absent (the client renders `message_key`). `fallback: "checkout"` tells the client to call `goToCheckout`. `fields` maps field key → text key for validation errors.

| HTTP | `code` | `fallback` | When |
| --- | --- | --- | --- |
| 400 | `invalid_request` | – | body not JSON / missing required key |
| 401 | `invalid_token`, `token_expired` | – | client silently re-opens a session once, then falls back |
| 403 | `origin_not_allowed` | `checkout` | |
| 403 | `module_disabled` | `checkout` | mode not `cod_form`, module off, or gate `cod_form_core` denied |
| 404 | `shop_not_found` | `checkout` | |
| 409 | `cap_reached` | `checkout` | CAP-6 behaviour `fallback`, or grace exhausted |
| 409 | `total_changed` | – | submit: recomputed total ≠ `expected_total_cents`; body also has `quote` |
| 409 | `already_processing` | – | a submit for this session is in flight; body has `poll_after_ms` |
| 410 | `upsell_expired` | – | |
| 422 | `validation_failed` | – | `fields` filled |
| 422 | `not_eligible` | – | COD rule failed; body has `eligibility` (same shape as in the quote) |
| 422 | `blocked` | – | block list |
| 422 | `limit_reached` | – | FRD-2 / FRD-3 |
| 422 | `bot_suspected` | – | honeypot filled or submitted faster than `min_submit_ms`. Message is the generic `error_generic`. |
| 422 | `no_shipping_rate` | – | SHP-4 |
| 422 | `out_of_stock` | – | ORD-7; `fields: {"items": "error_out_of_stock"}` |
| 422 | `discount_invalid` | – | |
| 422 | `otp_invalid`, `otp_attempts_exceeded` | – | |
| 428 | `otp_required` | – | submit without a verified OTP when one is required and the session has no OTP bypass (D.4) |
| 429 | `rate_limited`, `otp_throttled` | – | `retry_after` seconds |
| 502 | `order_failed` | – | Shopify error creating the order; safe to retry with the same idempotency key |
| 503 | `kill_switch` | `checkout` | |

**D.0.4 Throttles** (owner WS3 writes them as a snippet for `config/initializers/rack_attack.rb`; limits can be overridden by `cod_form_global_settings.settings["rate_limits"]`, read once at boot):

| Name | Key | Limit |
| --- | --- | --- |
| `codf/session/ip` | ip | 30 / 60 s |
| `codf/quote/ip` | ip | 120 / 60 s |
| `codf/orders/ip` | ip | 30 / 600 s |
| `codf/orders/shop` | `params["shop"]` | 600 / 60 s |
| `codf/otp/ip` | ip | 10 / 600 s |
| `codf/events/ip` | ip | 240 / 60 s |
| `cod_orders/ip` (legacy endpoint) | ip | 30 / 600 s |

Per-phone limits are enforced in the services with `CodForm::RateLimiter.hit!(key, limit:, period:)` (`Rails.cache.increment`, Redis-backed): `codf:otp:<shop_id>:<phone>` 5 / 600 s, `codf:order:<shop_id>:<phone>` 5 / 600 s. The existing `req/ip` rule (40 / 5 s) stays as is. Throttled response for `/api/form/*`: 429 with the error envelope (`Rack::Attack.throttled_responder` checks the path prefix; other paths keep the default body).

### D.1 `POST /api/form/session` — `Api::Form::SessionsController#create`

No token. Request:

```json
{
  "v": 37,
  "source": "product",
  "page_url": "https://brand.hu/products/widget?utm_source=fb",
  "locale": "hu", "country": "HU", "currency": "HUF",
  "items": [{"variant_id": "44111", "quantity": 2, "properties": {"Engraving": "Anna"}, "selling_plan": null}],
  "form_id": null,
  "preview_token": null,
  "recovery_token": null,
  "client_id": "b0f6…", "device": "mobile",
  "assets_base": "https://cdn.shopify.com/extensions/<uuid>/<version>/assets/",
  "attribution": {"utm_source": "fb", "fbclid": "…"},
  "tracking": {"fbp": "fb.1.…", "fbc": "", "ttp": "", "ttclid": "", "ga_client_id": ""},
  "consent": {"analytics": true, "marketing": true, "sale_of_data": true},
  "ab": {"3": "a"}
}
```

`source` ∈ B.8 list. For `cart`/`drawer` the client sends the items it read from `/cart.js` (variant, quantity, properties) — the server re-prices them. Cart items may also carry `"cart_line_price_cents"` (`final_line_price` from `/cart.js`); it is **never** used as a price, only to detect bundle-app carts: when a line has a property key starting with `_` and its cart price is lower than the server price × quantity, the session answers `fallback: "bundle_cart"` and the client goes to Shopify checkout with funnel reason `bundle_cart` (OFF-9). Bundle-app properties on lines that are **not** cheaper than the server price (apps without a cart transform) pass through to the order unchanged. `ab` echoes assignments the browser already holds (localStorage `codkf_ab`), so a returning visitor keeps its variant.

Response 200:

```json
{
  "ok": true,
  "token": "v1.eyJzaWQiOi…​.c2ln",
  "session_id": "0b6c9c2e-…",
  "expires_at": "2026-10-03T12:00:00Z",
  "config_version": 37,
  "fallback": null,
  "test": false,
  "cap": {"state": "ok"},
  "locale": "hu", "rtl": false,
  "form": { "id": 5, "version": 12, "config": { "…": "published_config, C.2, with texts reduced to the active locale + en" } },
  "countries": [{"code": "HU", "name": "Magyarország", "dial_code": "36"}],
  "country_schema": { "…": "E.10 schema for the buyer country" },
  "otp": {"enabled": true, "mode": "before_order", "channels": ["sms", "whatsapp"], "max_attempts": 3, "resend_wait_seconds": 30, "code_length": 4},
  "offers": {
    "quantity": { "…": "matching quantity offer, C.4, or null" },
    "bumps": [ { "id": 21, "config": { "…": "C.4 bump" }, "unit_price_cents": 49900 } ],
    "downsell": { "id": 30, "config": { "…": "…" } },
    "thresholds": [ ],
    "upsell_enabled": true
  },
  "features": {"discount_code": true, "custom_fields": false, "autocomplete": false, "pay_online": true, "hide_branding": false},
  "autocomplete": {"google_api_key": ""},
  "pixels": [ { "…": "C.6 storefront representation" } ],
  "event_ids": {"initiate_checkout": "codkf_0b6c9c2e_ic"},
  "handoff": {"storefront_token": "shpat-public-…", "dummy_variant_id": null},
  "security": {"min_submit_ms": 3000, "honeypot": "codkf_company_url"},
  "prefill": null,
  "ab": {"3": "a"},
  "quote": { "…": "D.2 quote computed without an address" }
}
```

- `fallback` non-null (`"kill_switch"`, `"module_disabled"`, `"cap_reached"`, `"config_error"`, `"not_eligible_country"`, `"bundle_cart"`) is returned with HTTP 200 and `ok: true` **and no token**: this is the one deliberate exception to D.0.3, so that a fallback is not an error in monitoring. The client calls `goToCheckout`.
- `cap.state`: `ok`, `grace` (over cap, inside grace), `flagged` (over cap, behaviour `flag_only`), `fallback`.
- `otp.max_attempts` = `Setting#max_retries` clamped to 1–5 (3 when nil); `otp.resend_wait_seconds` = `Setting#otp_wait_time` (30 when nil or ≤ 0); `otp.mode` default `before_order`.
- `features.hide_branding` is true only with gate `branding_removal` **and** `general.branding.hide_powered_by`; otherwise the form shows the `powered_by` line under the submit button.
- `handoff.storefront_token` is `Setting#store_front_token`; present only when the partial step or Pay online can occur. `dummy_variant_id` is `Setting#partial_dummy_variant_id` when partial payment is enabled.
- `prefill` (recovery only): `{"contact": {...}, "address": {...}, "items": [...], "discount": {"type","value"}}`.
- Server steps: availability → cap (`CodForm::CapService.state(shop)`) → preview token (`is_test`) → pick form (`CodForm::Engine::FormTargeting`) → `CodForm::CatalogService.lines(shop, items, country:)` → offers (`CodForm::OfferResolver`, including A/B assignment) → `CodForm::QuoteService` → create `CodForm::Session` → funnel event `cf_form_open` (server-side) → `CodForm::Tracking::ServerDispatchJob` for InitiateCheckout.
- p95 budget 350 ms with a warm catalog cache.

### D.2 `POST /api/form/quote` — `Api::Form::QuotesController#create`

Request:

```json
{
  "token": "…",
  "seq": 4,
  "items": [{"variant_id": "44111", "quantity": 3, "properties": {}}],
  "address": {"country": "HU", "province": "BU", "city": "Budapest", "zip": "1051"},
  "contact": {"phone": "301234567", "email": ""},
  "shipping_rate_id": 4,
  "bumps": [{"offer_id": 21, "quantity": 1}],
  "discount_code": "WELCOME10",
  "downsell_offer_id": null,
  "want_tax": false
}
```

Response 200:

```json
{
  "ok": true,
  "seq": 4,
  "quote": {
    "currency": "HUF",
    "lines": [
      {"key": "l0", "variant_id": "44111", "product_id": "8111", "title": "Widget", "variant_title": "Blue", "image": "https://…", "quantity": 3,
       "unit_price_cents": 199900, "compare_at_cents": 249900, "line_subtotal_cents": 599700,
       "discount_cents": 150000, "discount_title": "3 packs", "line_total_cents": 449700,
       "kind": "product", "available": true, "max_quantity": 10}
    ],
    "extra_lines": [
      {"key": "bump_21", "kind": "bump", "offer_id": 21, "title": "Express handling", "quantity": 1, "unit_price_cents": 49900, "line_total_cents": 49900}
    ],
    "quantity_offer": {"offer_id": 12, "applied_tier_index": 2, "savings_cents": 150000},
    "discounts": [
      {"kind": "quantity_offer", "title": "3 packs", "amount_cents": 150000},
      {"kind": "discount_code", "title": "WELCOME10", "amount_cents": 49960, "code": "WELCOME10"}
    ],
    "discount_code": {"code": "WELCOME10", "status": "applied", "message_key": null},
    "shipping": {
      "rates": [{"id": 4, "name": "Standard delivery", "description": "2–4 business days", "price_cents": 149000}],
      "selected_id": 4, "price_cents": 149000, "hide_selector": true, "message": null
    },
    "cod_fee": {"enabled": true, "label": "Cash on delivery fee", "amount_cents": 50000, "taxable": false},
    "tax": {"status": "included", "required": false, "amount_cents": 0, "lines": []},
    "subtotal_cents": 599700,
    "discount_total_cents": 199960,
    "merchandise_total_cents": 449640,
    "shipping_cents": 149000,
    "total_cents": 648640,
    "savings_cents": 349960,
    "eligibility": {"cod_allowed": true, "reasons": [], "message_key": null, "message": null, "pay_online": true},
    "payment_options": null,
    "otp_required": true,
    "thresholds": [{"offer_id": 40, "kind": "free_shipping", "threshold_cents": 1500000, "remaining_cents": 851360, "reached": false}],
    "warnings": []
  }
}
```

- `seq` is echoed; the client drops responses older than the last one it applied.
- `merchandise_total_cents` = product lines after all discounts + bump/gift lines. `total_cents` = `merchandise_total_cents + shipping_cents + cod_fee.amount_cents + tax.amount_cents` (tax added only when `tax.status == "calculated"` and prices exclude tax).
- `tax.status`: `included` (shop prices include tax or `Setting#is_tax_included_with_product`), `none` (address incomplete, or tax not requested), `calculated` (from `ShopifyServices::DraftOrderCalculateService`, cached 10 min on a hash of lines + address; requested when the client sends `want_tax: true`), `unavailable`. `tax.required` is true when the shop's prices exclude tax (`shop.taxesIncluded == false` and `Setting#is_tax_included_with_product` is false): the client then sends `want_tax: true` as soon as country, province (where the schema has one) and zip are filled, and always before submit, so the total it shows and sends as `expected_total_cents` includes tax (ORD-3). When `required` is false no Shopify call is made for a quote. The tax call is made only when the address is complete (never per keystroke); while it is pending the client shows the tax line in a loading state and disables submit; results are cached per session by address + cart fingerprint (and 10 min in `Rails.cache`). Targets: quote without the tax call ≤ 400 ms p95 (NFR-4), with it ≤ 1.2 s p95. If the tax call fails twice the quote returns `tax.status: "unavailable"`, submit is enabled again, the server recomputes at order creation, and a different total comes back as 409 `total_changed` (`error_total_changed`) with the new quote for the buyer to confirm.
- `eligibility.reasons` — codes of E.3 / E.9. `pay_online` tells the client whether to show the Pay online button with the message.
- `payment_options` — null when no enabled `PartialRuleSet` matches (PRE-8); otherwise:

```json
{
  "options": [
    {"id": "cod", "kind": "cod", "title_key": "payment_full_cod", "pay_now_cents": 0, "pay_later_cents": 648640, "description": "Pay Ft6 486 on delivery", "rule_id": null},
    {"id": "rule_17", "kind": "partial", "title_key": "payment_partial", "pay_now_cents": 100000, "pay_later_cents": 498640, "description": "Pay Ft1 000 now and Ft4 986 on delivery", "rule_id": 17, "discount_cents": 50000},
    {"id": "rule_18", "kind": "prepaid", "title_key": "payment_prepaid", "pay_now_cents": 583776, "pay_later_cents": 0, "description": "Pay now and save 10%", "rule_id": 18, "discount_cents": 64864}
  ],
  "default_id": "cod"
}
```

- `payment_options`: Full COD (`id: "cod"`) is always the first option and the `default_id` whenever COD is allowed for the buyer; it is absent only when RTO gating or a COD rule removed COD. When COD is removed and no partial/prepaid rule matches, `payment_options` is null and `eligibility` carries the merchant message with `pay_online: true`.
- The quote is saved to `cod_form_sessions.quote_snapshot` and `cart_snapshot`.
- Errors: only transport-level errors (401/429/400). Ineligibility, missing rates and invalid codes are **data in a 200**, not errors.

### D.3 `POST /api/form/contact` — `Api::Form::ContactsController#create` (ABN-1)

Request `{"token", "contact": {"phone", "email", "first_name", "last_name"}, "address": {…partial…}, "country": "HU"}` → `{"ok": true}`. Saves to the session (normalised phone/email), nothing else. Called on blur of phone or email, at most once per changed value.

### D.4 `POST /api/form/otp/send` — `Api::Form::OtpController#send_code`

Request `{"token", "phone": "301234567", "country": "HU", "channel": "sms"}` (`channel` ∈ `sms`, `whatsapp`).
Response `{"ok": true, "sent": true, "channel": "sms", "resend_wait_seconds": 30, "attempts_left": 2, "masked_phone": "+36 •• ••• 4567"}`.

`CodForm::OtpService.send_code(session:, phone:, country:, channel:, ip:)`:
1. `Engine::Phone.validate` → 422 `validation_failed` (`fields.phone`).
2. Block list + `RateLimiter` → 422 `blocked` / 429 `otp_throttled`.
3. `session.otp["sends"] < Setting#max_retries.clamp(1, 5)` (default 3 when nil) else 422 `otp_attempts_exceeded` (OTP-2).
4. Calls the existing service unchanged (F11):
   `NetworkServices::SendPreOrderOtpService.call(shop.id, {"country_code" => "HU", "phone" => national_digits, "mode" => (channel == "whatsapp" ? "WHATSAPP" : "SMS"), "ip_address" => ip, "device_id" => session.public_id})` — **no** `cart_details` (F12).
5. Maps the result: `status == "Success"` → ok; `code == "pre_order_otp_throttled"` → 429 `otp_throttled`; `code == "pre_order_otp_phone_blocked"` → 422 `blocked`. **Send failure on our side** (result nil, or `status == "Error"` with no `code` — shop locked / balance exhausted / provider error — or `code == "checkout_otp_plan_forbidden"`) → **OTP bypass**: response 200 `{"ok": true, "sent": false, "bypass": true}`, `session.otp["bypassed"] = true`, funnel event `cf_otp_bypassed` with `meta.reason = "otp_unavailable"`. The buyer sees no error; the form goes straight to the next step; the order is created **unverified** (no verification tag, no `_otpVerifiedPhoneNumber`), so it gets the shop's post-order verification (F.5). Throttling, a blocked phone, a wrong code and exhausted attempts never bypass: they show the error with "Change number" and "Pay online".
6. Session `status = "otp_pending"`, `otp.sends += 1`; funnel event `cf_otp_sent`.

### D.5 `POST /api/form/otp/verify` — `Api::Form::OtpController#verify`

Request `{"token", "phone": "301234567", "country": "HU", "code": "4821"}`.
Response `{"ok": true, "verified": true}`; wrong code → 422 `otp_invalid` with `attempts_left`.
Calls `NetworkServices::VerifyPreOrderOtpService.call(shop.id, {"country_code", "phone", "otp", "ip_address", "device_id" => session.public_id, "email" => session email})` and reads `result["verification"]`. The `shippingAddress`, `customerLogin` and `sso_session_token` keys of the result are discarded (no cookie is set), except in phone-first mode (FRM-18), where `shippingAddress` is returned as `"saved_addresses"` — only after a successful verification. On success: `session.otp_verified_at = now`, `contact.phone_e164` frozen (a later submit with a different phone returns 428 `otp_required`); funnel event `cf_otp_verified`.

### D.6 `POST /api/form/orders` — `Api::Form::OrdersController#create`

Request:

```json
{
  "token": "…",
  "idempotency_key": "0b6c9c2e-…:1",
  "items": [{"variant_id": "44111", "quantity": 3, "properties": {}}],
  "contact": {"first_name": "Anna", "last_name": "Kiss", "phone": "301234567", "email": "anna@example.com"},
  "address": {"country": "HU", "province": "BU", "city": "Budapest", "zip": "1051", "address1": "Fő utca 1", "address2": ""},
  "custom_fields": {"cf_a1b2c3d4": "Leave at the door"},
  "fields": {"gst_number": "", "note": ""},
  "marketing_consent": false,
  "shipping_rate_id": 4,
  "bumps": [{"offer_id": 21, "quantity": 1}],
  "discount_code": "WELCOME10",
  "downsell_offer_id": null,
  "payment_option_id": "cod",
  "expected_total_cents": 648640,
  "elapsed_ms": 48211,
  "codkf_company_url": "",
  "tracking": {"fbp": "", "fbc": "", "ttp": "", "ttclid": "", "ga_client_id": "", "page_url": "…", "user_agent": "…"},
  "attribution": {}
}
```

`idempotency_key` = `"<session_id>:<n>"`, where `n` starts at 1 and increases only when the buyer changes the form after a **failed** submit; retries of the same attempt reuse the key. The server additionally enforces one order per session (ORD-4).

Response 201:

```json
{
  "ok": true,
  "order": {"id": "6123456789", "name": "#1042", "number": 1042, "total_cents": 648640, "currency": "HUF", "status_url": "https://brand.hu/…/orders/…"},
  "thank_you": {"type": "order_status", "url": "https://brand.hu/…/orders/…", "message": null, "whatsapp_url": null},
  "upsell": {"offer_id": 33, "config": { "…": "C.4 upsell" }, "variant": {"id": "44123", "title": "…", "image": "…", "price_cents": 99900, "discounted_price_cents": 79920}, "expires_at": "2026-10-03T10:21:00Z"},
  "events": {"purchase_event_id": "order_6123456789_purchase", "value_cents": 648640, "currency": "HUF", "content_ids": ["44111"], "num_items": 3},
  "web_pixel": {"orderId": "6123456789", "totalPrice": "6486.40", "currencyCode": "HUF", "email": "anna@example.com", "attribution": {}},
  "test": false
}
```

A replay (same session, order already created) returns **200** with the same body. 202 `{"ok": true, "status": "processing", "poll_after_ms": 1500}` is returned when `async_orders` is on and the order is not finished after 8 s (ORD-9); the client then polls D.7. Processing order is specified in F.2.

### D.7 `POST /api/form/orders/status` — `Api::Form::OrdersController#status`

Request `{"token"}` → 200 with the D.6 body when `ordered`; 202 processing; 502 `order_failed` (with the stored `order_error`) when the background attempt failed.

### D.8 `POST /api/form/handoff` — `Api::Form::HandoffsController#create` (PRE-1, PRE-9)

Request `{"token", "kind": "partial"|"prepaid", "payment_option_id": "rule_17", "contact": {...}, "address": {...}, "items": [...], "reason": "buyer_choice"|"blocked"|"preset_a"}`.
Response:

```json
{
  "ok": true,
  "kind": "partial",
  "cart_attributes": {
    "_codkFormSessionId": "0b6c9c2e-…", "_codkFormId": "5", "_codkSessionId": "0b6c9c2e-…",
    "_otpVerifiedPhoneNumber": "+36301234567", "_codkCountryCode": "HU",
    "_codkAmountType": "fixed", "_codkAmountValue": "1000.0", "_codkCheckoutMode": "",
    "_codkFinalDiscountValue": "", "_codkPaymentDescription": "Pay Ft1 000 now and Ft4 986 on delivery",
    "_codkDiscounts": "orderLevel:500|PARTIAL5", "_codkImageURLs": "44111:https%3A%2F%2F…",
    "_codkOriginalTotal": "5997", "_partial_product_variant": "45999", "partial_payment_variants": "[44111]", "_partialPaymentProduct": true
  },
  "discount_code": "PARTIAL5",
  "buyer_identity": {"email": "anna@example.com", "phone": "+36301234567", "countryCode": "HU",
    "deliveryAddressPreferences": [{"deliveryAddress": {"firstName": "Anna", "lastName": "Kiss", "address1": "Fő utca 1", "address2": "", "city": "Budapest", "province": "BU", "country": "HU", "zip": "1051", "phone": "+36301234567"}}]},
  "storefront_token": "…",
  "checkout_path": "/checkout"
}
```

For `kind: "prepaid"` only `_codkFormSessionId`, `_codkFormId`, the OTP attributes (when verified), the quantity-offer / downsell `_codkDiscounts` string (OFF-4) and, when PRE-2 applies, the existing prepaid-discount attribute are returned. The server computes everything with `CodForm::Engine::PartialRules.handoff_attributes` (E.11), sets the session `status` to `handoff_partial` / `handoff_prepaid`, stores `partial_rule_set_id`, and writes funnel event `cf_partial_handoff` / `cf_prepaid_redirect`. `_otpVerifiedPhoneNumber` is included **only** when `session.otp_verified_at` is set. The client steps are in G.9.

### D.9 `POST /api/form/upsell_accept` — `Api::Form::UpsellsController#accept` (OFF-10)

Request `{"token", "offer_id": 33, "accept": true}` → `{"ok": true, "order": {"id", "name", "total_cents"}, "added": {"variant_id", "quantity", "price_cents"}}`. `accept: false` records the decline and returns `{"ok": true}`. Errors: 410 `upsell_expired`, 422 `out_of_stock`, 502 `order_failed`. Service in F.6.

### D.10 `POST /api/form/events` — `Api::Form::EventsController#create`

Token optional (button views happen before a session exists). Request:

```json
{"token": null, "client_id": "b0f6…", "events": [
  {"type": "cf_button_view", "at": "2026-10-03T09:58:01Z", "meta": {"page": "product", "product_id": "8111", "country": "HU", "device": "mobile"}},
  {"type": "cf_first_input", "at": "…", "meta": {"field": "phone"}}
]}
```

Always `204`. Max 20 events per call; unknown types are dropped. Sent with `navigator.sendBeacon` (a `Blob` of type `text/plain`). Handling in I.1. The existing `POST /form_funnel/ingest` is left untouched for Express.

### D.11 Geo datasets

- `GET /api/form/geo/:country?shop=…&locale=hu` — `Api::Form::GeoController#show` → `{"country": "HU", "schema": {E.10}, "provinces": [{"code": "BU", "name": "Budapest"}], "cities": {"mode": "free"|"list"|"by_province", "list": ["…"], "by_province": {"BU": ["…"]}}}`. `Cache-Control: public, max-age=86400`. Data: `lib/cod_form/geo/<CC>.json` when the file exists, otherwise provinces from the existing `provinces` table and `cities.mode = "free"` (the dataset source for the launch markets is still open — spec §17).
- `GET /api/form/geo/:country/postal/:code?shop=…` — `#postal` → `{"found": true, "city": "Pune", "province": "MH"}` from the existing `locations` table (`Location.where(zipcode:, country:)`, as `order_confirmations#zip_details` does). Used for India (FRM-6); returns `{"found": false}` for countries without data.

Both are `GET`, no token, origin-checked, throttled by `codf/quote/ip`.

### D.12 Legacy `POST /api/cod_orders` (kept, backward compatible)

No request or response change. Added by WS3: the `cod_orders/ip` throttle, and `CodForm::OriginGuard` in **log-only** mode unless `ENV["COD_ORDERS_ORIGIN_ENFORCE"] == "true"`. It keeps calling `CodOrderCreateService` with the positional signature (F1). Requiring the session token on this endpoint (spec §14 "now requires the session token") is **not** done, because the Express client cannot send one; the new flow uses `/api/form/orders` (decision 11).

### D.13 Routes to add (storefront) — owner WS3

Inside the existing `namespace :api do … end` block that holds `resources :cod_orders` (`config/routes.rb:357-508`):

```ruby
namespace :form do
  post 'session',        to: 'sessions#create'
  post 'quote',          to: 'quotes#create'
  post 'contact',        to: 'contacts#create'
  post 'otp/send',       to: 'otp#send_code'
  post 'otp/verify',     to: 'otp#verify'
  post 'orders',         to: 'orders#create'
  post 'orders/status',  to: 'orders#status'
  post 'handoff',        to: 'handoffs#create'
  post 'upsell_accept',  to: 'upsells#accept'
  post 'events',         to: 'events#create'
  get  'geo/:country',               to: 'geo#show',   constraints: { country: /[A-Za-z]{2}/ }
  get  'geo/:country/postal/:code',  to: 'geo#postal', constraints: { country: /[A-Za-z]{2}/, code: /[A-Za-z0-9 \-]{2,12}/ }
end
```

And outside it (public, no auth): `get '/cod_form/preview_frame', to: 'cod_form_admin/preview_frames#show'` (H.6) and `get '/cod_form/google/callback', to: 'cod_form_admin/google_oauth#callback'` (I.5).

### D.14 Admin API — common rules

- Controllers in `app/controllers/cod_form_admin/`, module `CodFormAdmin`, base `CodFormAdmin::BaseController < AuthenticatedController` (F24). `@shop` comes from the inherited `set_shop`; the base adds `before_action :load_config` (`@config = CodForm::ShopConfig.for(@shop)`), `before_action :require_module!` (403 `{"error": "module_disabled"}` unless the module is available to the shop; `bootstrap` is exempt) and a `rescue_from ActiveRecord::RecordInvalid` → 422.
- Paths start with `/cod_form/`. JSON in, JSON out, `snake_case`, **no key transformation** (H.3).
- Success: the resource (or `{"items": [...], "meta": {...}}` for lists). Validation error: 422 `{"error": "validation_failed", "errors": {"<path>": ["message"]}}`. Gate error: 402 `{"error": "upgrade_required", "feature": "order_bumps", "min_tier": "pro"}`. Not found: 404 `{"error": "not_found"}`.
- Every write calls `@config.bump_version!` when it changes storefront behaviour, and `CodForm::MerchantAudit.record` (DSH-14).

### D.15 Admin endpoints

| Method + path | Controller#action | Request → response |
| --- | --- | --- |
| `GET /cod_form/bootstrap` | `bootstrap#show` | → `{"module_enabled": true, "mode": "legacy"\|"cod_form", "legacy_mode_label": "express"\|"checkout", "tier": "free", "gates": {"<feature_key>": {"allowed": true, "min_tier": "free"}}, "usage": {"period": "2026-10", "orders": 12, "cap": 50, "state": "ok", "behaviour": "fallback", "percent": 24}, "currency": "HUF", "money_format": "{{amount}} Ft", "shop_country": "HU", "locales": ["hu","en"], "preview": {"asset_base": "https://cdn.shopify.com/extensions/…/assets/", "frame_url": "/cod_form/preview_frame"}}` |
| `GET /cod_form/setup` | `setup#show` | → `{"mode", "general": {B.1.1}, "setup_state": {…}, "checklist": [{"key": "embed", "done": true}, {"key": "preset"}, {"key": "shipping_rate"}, {"key": "test_order"}], "health": [{"code": "embed_off"\|"legacy_embed_on"\|"no_shipping_rate"\|"no_country"\|"cap_reached"\|"cap_flagged"\|"otp_unavailable"\|"rule_cod_fee_ignored"\|"zip_allow_list_no_exact", "severity": "critical"\|"warning"\|"info", "count": null, "action_url": "…"}], "embed": {"enabled": false, "legacy_enabled": true, "theme_editor_url": "https://<shop>/admin/themes/current/editor?context=apps&activateAppId=<uuid>/cod-form-embed"}, "preview_url": "https://<primary domain>/?codk_preview=<token>", "usage": {…}}` |
| `PUT /cod_form/setup` | `setup#update` | `{"general": {…partial B.1.1…}}` → same as GET |
| `POST /cod_form/mode` | `setup#mode` | `{"mode": "cod_form"\|"legacy"}` → `{"mode", "enabled_at"}`. Turning on runs `CodForm::EnableService` (creates the default form + default button config when missing, fills `general.countries` with `shops.country_code` on the first enable, syncs domains and the metafield). The switch is never blocked by a health item. Nothing in `Setting` is changed (DSH-5). |
| `POST /cod_form/setup/refresh_embed` | `setup#refresh_embed` | → `{"embed": {…}}` (re-reads the theme's `settings_data.json`) |
| `POST /cod_form/setup/test_order` | `setup#test_order` | → `{"preview_url"}` (rotates `preview_token`) |
| `GET /cod_form/button` | `buttons#show` | → `{"preset": "B", "config": {C.1.2 stored keys}}` |
| `PUT /cod_form/button` | `buttons#update` | `{"preset", "config"}` → same; preset `A` requires gate `preset_a` |
| `GET /cod_form/forms` | `forms#index` | → `{"items": [{"id","name","is_default","status","position","targeting","published_at","published_version","has_unpublished_changes"}]}` |
| `POST /cod_form/forms` | `forms#create` | `{"name", "template_key", "targeting"}` → form (gate `multiple_forms` for the 2nd+) |
| `GET /cod_form/forms/:id` | `forms#show` | → `{"id","name","is_default","targeting","template_key","draft_config","published_config","published_version","published_at"}` |
| `PUT /cod_form/forms/:id` | `forms#update` | `{"name","targeting","draft_config"}` → form, plus `"warnings": [...]`; never touches `published_config` |
| `POST /cod_form/forms/:id/publish` | `forms#publish` | → form; 422 when `normalize` reports errors |
| `POST /cod_form/forms/:id/discard_draft` | `forms#discard_draft` | → form (`draft_config = published_config`) |
| `POST /cod_form/forms/:id/duplicate` | `forms#duplicate` | → new form |
| `POST /cod_form/forms/:id/make_default` | `forms#make_default` | → `{"items": […]}` |
| `DELETE /cod_form/forms/:id` | `forms#destroy` | archives; the default form cannot be archived (422) |
| `GET /cod_form/forms/defaults` | `forms#defaults` | → `{"config": {default C.2}, "templates": [...], "texts": {"en": {...}, "hi": {...}, …}, "countries": [{"code","name"}]}` (texts from `config/cod_form/default_texts.json`) |
| `GET /cod_form/shipping_rates` | `shipping_rates#index` | → `{"items": [C.3]}` |
| `POST /cod_form/shipping_rates` | `#create` | C.3 without `id` → rate |
| `PUT /cod_form/shipping_rates/:id` | `#update` | → rate |
| `DELETE /cod_form/shipping_rates/:id` | `#destroy` | → 204 |
| `POST /cod_form/shipping_rates/reorder` | `#reorder` | `{"ids": [4,2,9]}` → `{"items"}` |
| `POST /cod_form/shipping_rates/import_csv` | `#import_csv` | multipart `file` (columns `name,description,price,country,province,min_total,max_total`), `mode=append\|replace` → `{"created": 12, "errors": [{"row": 3, "message": "…"}]}` (SHP-8) |
| `GET /cod_form/offers?type=quantity` | `offers#index` | → `{"items": [offer]}` |
| `POST /cod_form/offers` / `PUT /cod_form/offers/:id` / `DELETE /cod_form/offers/:id` | `offers#create/update/destroy` | C.4 wrapper → offer; 422 with `errors.targeting` on OFF-2 overlap; 402 per gate (`order_bumps`, `upsell`, `downsell`, `threshold_offers`) |
| `POST /cod_form/offers/:id/status` | `offers#status` | `{"status": "active"\|"paused"}` → offer |
| `GET/POST /cod_form/ab_tests`, `PUT/DELETE /cod_form/ab_tests/:id`, `POST /cod_form/ab_tests/:id/start`, `/stop` | `ab_tests#…` | B.6 shape; `PUT` is rejected with 422 once started; results come with `GET /cod_form/ab_tests/:id` as `"results": [{"key","views","accepts","orders","revenue_cents"}]` |
| `GET /cod_form/fraud` | `fraud#show` | → `{"fraud": {B.1.2}, "otp": {general.otp}, "rto": {general.rto}, "shop_otp_enabled": true}` |
| `PUT /cod_form/fraud` | `fraud#update` | same keys → same |
| `GET /cod_form/block_entries?kind=phone&q=&page=1` | `block_entries#index` | → `{"items": [C.5], "meta": {"page","pages","count"}}` |
| `POST /cod_form/block_entries` | `#create` | `{"kind","value","note"}` or `{"kind","values": ["…"]}` (bulk / file upload parsed client-side, max 5 000) → `{"created": n, "skipped": n}` |
| `DELETE /cod_form/block_entries/:id` | `#destroy` | → 204 |
| `GET /cod_form/rejections?page=1&reason=` | `rejections#index` | → `{"items": [B.9 columns], "meta"}` (FRD-6) |
| `GET /cod_form/pixels` | `pixels#index` | → `{"items": [C.6]}` |
| `POST /cod_form/pixels` / `PUT /cod_form/pixels/:id` / `DELETE /cod_form/pixels/:id` | `pixels#…` | C.6 with `access_token` (write-only) → pixel; gates `extra_pixels` (2nd+ pixel of a platform) and `pixels_p3` (snapchat, pinterest, product targeting) are checked (both free in the seed); 422 `pixel_limit` beyond 5 pixels per platform |
| `POST /cod_form/pixels/:id/test` | `pixels#test` | → `{"ok": true, "response": {...}}` (sends a test event server-side) |
| `GET /cod_form/integrations` | `integrations#index` | → `{"items": [{"provider","status","config","last_error","last_success_at"}]}` |
| `PUT /cod_form/integrations/:provider` | `integrations#update` | `{"credentials": {...}, "config": {...}}` → item |
| `DELETE /cod_form/integrations/:provider` | `integrations#destroy` | → 204 |
| `GET /cod_form/integrations/google_sheets/auth_url` | `google_oauth#auth_url` | → `{"url"}` |
| `GET /cod_form/integrations/google_sheets/sheets` | `google_oauth#sheets` | → `{"spreadsheets": [{"id","name"}]}` |
| `GET /cod_form/analytics?from=&to=&country=&device=&product_id=&compare=1` | `analytics#show` | → `{"range": {"from","to"}, "funnel": [{"step": "button_views","count": 0}, …], "totals": {"orders","revenue_cents","aov_cents","conversion_rate","prepaid_redirects","partial_handoffs"}, "series": [{"date","form_opens","orders","revenue_cents"}], "previous": {…same totals…}, "currency"}` |
| `GET /cod_form/analytics/breakdown?by=utm_campaign\|offer\|country\|device\|product\|form&from=&to=` | `analytics#breakdown` | → `{"rows": [{"key","form_opens","orders","revenue_cents","conversion_rate"}]}` (ANL-4) |
| `GET /cod_form/analytics/export.csv?…` | `analytics#export` | CSV (ANL-4) |
| `GET /cod_form/usage` | `usage#show` | → `{"period","orders","partial_orders","cap","state","behaviour","grace_orders","percent","overage": {"rate","count","billed"}, "history": [{"period","orders"}]}` |

### D.16 Routes to add (admin) — owner WS6 delivers a snippet; the integrator (WS3, owner of `config/routes.rb`) merges it

```ruby
scope '/cod_form', module: 'cod_form_admin', as: 'cod_form_admin' do
  get  'bootstrap', to: 'bootstrap#show'
  get  'setup', to: 'setup#show'
  put  'setup', to: 'setup#update'
  post 'mode',  to: 'setup#mode'
  post 'setup/refresh_embed', to: 'setup#refresh_embed'
  post 'setup/test_order',    to: 'setup#test_order'
  get  'button', to: 'buttons#show'
  put  'button', to: 'buttons#update'
  get  'forms/defaults', to: 'forms#defaults'
  resources :forms, only: %i[index show create update destroy] do
    member { post :publish; post :discard_draft; post :duplicate; post :make_default }
  end
  resources :shipping_rates, only: %i[index create update destroy] do
    collection { post :reorder; post :import_csv }
  end
  resources :offers, only: %i[index show create update destroy] do
    member { post :status }
  end
  resources :ab_tests, only: %i[index show create update destroy] do
    member { post :start; post :stop }
  end
  get 'fraud', to: 'fraud#show'
  put 'fraud', to: 'fraud#update'
  resources :block_entries, only: %i[index create destroy]
  resources :rejections, only: %i[index]
  resources :pixels, only: %i[index create update destroy] do
    member { post :test }
  end
  get    'integrations', to: 'integrations#index'
  get    'integrations/google_sheets/auth_url', to: 'google_oauth#auth_url'
  get    'integrations/google_sheets/sheets',   to: 'google_oauth#sheets'
  put    'integrations/:provider', to: 'integrations#update'
  delete 'integrations/:provider', to: 'integrations#destroy'
  get 'analytics',            to: 'analytics#show'
  get 'analytics/breakdown',  to: 'analytics#breakdown'
  get 'analytics/export',     to: 'analytics#export', defaults: { format: :csv }
  get 'usage', to: 'usage#show'
end
```

Page routes (HTML shell for the React app), added **inside** the `settings_pages` lambda (`config/routes.rb:741`) so they exist bare and under `/settings-hub` (DSH-2), plus one analytics path next to the other `/usage-analytics/*` lines (`config/routes.rb:732-737`):

```ruby
get '/features/cod-form(/*section)', to: 'home#index', format: false
get '/integrations/tiktok',         to: 'home#index'
get '/integrations/google-sheets',  to: 'home#index'
get '/integrations/form-pixels',    to: 'home#index'
# outside the lambda:
get '/usage-analytics/cod-form', to: 'usage_analytics#index'
```

Internal admin routes are in J.3.

---

## E. Pure-Ruby engines (`app/services/cod_form/engine/`, module `CodForm::Engine`)

Rules for every class: class methods only, no state, no I/O, no clock (time is passed in), string-keyed hashes, integer cents, deterministic. Tests: `test/services/cod_form/engine/<name>_test.rb`, each starting with `require "minitest/autorun"` and `require_relative "../../../../app/services/cod_form/engine/<name>"`; run with `ruby test/services/cod_form/engine/<name>_test.rb`. A runner `test/services/cod_form/engine/all.rb` requires every `*_test.rb`.

### E.1 `Money` (`money.rb`)

```ruby
Money.percent_of(cents, percent)            # => Integer, round half up: ((cents * percent) / 100.0).round
Money.round_to_half_unit(cents)             # => Integer; nearest 50 cents (mirrors F5: (x*2).round/2.0)
Money.allocate(total_cents, weights)        # => [Integer]; largest-remainder split of total across weights, sums exactly
Money.to_decimal_string(cents)              # => "6486.40"
Money.clamp_non_negative(cents)             # => Integer
Money.format(cents, format)                 # => "6 486 Ft"; format = {"template"=>"{{amount}} Ft","decimals"=>0,"thousands"=>" ","decimal"=>","}
```

`format` is derived once per shop from `shops.money_format` by `CodForm::MoneyFormatAdapter` and passed to any engine that produces buyer-visible strings.

### E.2 `PostalMatcher` (`postal_matcher.rb`) — RUL-2

```ruby
PostalMatcher.parse(list)                   # list: String ("110001, 4000*, 560001-560100") or Array<String>
  # => [{"type"=>"exact","value"=>"110001"}, {"type"=>"prefix","value"=>"4000"}, {"type"=>"range","from"=>"560001","to"=>"560100"}]
PostalMatcher.match?(code, patterns)        # => true/false
PostalMatcher.normalize(code)               # upcase, strip spaces and hyphens
```

- Separators: comma, semicolon, newline. Entry syntax: `ABC*` prefix; `A-B` range; anything else exact.
- An entry containing `-` is a range only when both sides are all digits **and** have the same length after normalisation (so the Polish `00-950` or the Dominican `10101-1234` stay exact); a numeric range compares integers.
- Exact and prefix comparisons use the normalised form (case-insensitive, spaces and hyphens removed).
- `match?("", …)` is false.

### E.3 `CodRules` (`cod_rules.rb`) — RUL-1, VIS-6

Mirrors the payment customization function (F14) so form and checkout agree.

```ruby
CodRules.evaluate(rules:, cart:, address:, contact:, stage:)
# rules   (built by CodForm::RulesAdapter.from_setting(setting)):
#   {"allow_countries"=>["HU"], "allow_provinces"=>["BU"], "deny_provinces"=>[],
#    "allow_zips"=>"…raw string…", "deny_zips"=>"…",
#    "deny_product_ids"=>[], "allow_product_ids"=>[], "deny_variant_ids"=>[],
#    "allow_collection_ids"=>[], "deny_collection_ids"=>[],
#    "deny_vendors"=>[], "allow_vendors"=>[],
#    "min_total_cents"=>nil, "max_total_cents"=>nil,
#    "deny_phones"=>[], "deny_emails"=>[], "hide_gift_cards"=>false}
# cart    {"lines"=>[E.7 line hashes], "total_cents"=>Integer}
# address {"country"=>"HU","province"=>"BU","zip"=>"1051"}   (may be partial)
# contact {"phone_digits"=>"36301234567","email"=>"a@b.c"}
# stage   "page" | "quote" | "submit"
# => {"allowed"=>true|false, "reasons"=>["zip_not_allowed", ...], "pending"=>["zip"]}
```

| Setting column | Rule key | Semantics (same as the function) | Reason code |
| --- | --- | --- | --- |
| `selected_countries` | `allow_countries` | non-empty → country must be in list (case-insensitive) | `country_not_allowed` |
| `show_provinces` / `hide_provinces` | `allow_provinces` / `deny_provinces` | province code in / not in list | `province_not_allowed` |
| `selected_zips` / `excluded_zips` | `allow_zips` / `deny_zips` | `PostalMatcher` (exact, prefix, range) | `zip_not_allowed` |
| `selected_product_ids` | `deny_product_ids` | any line's product in list → deny | `product_not_allowed` |
| `show_product_ids` | `allow_product_ids` | non-empty → any line's product **not** in list → deny | `product_not_allowed` |
| `hide_product_variant_ids` | `deny_variant_ids` | any line's variant in list → deny | `product_not_allowed` |
| `excluded_collection_ids` | `deny_collection_ids` | any line's product in any listed collection → deny | `collection_not_allowed` |
| `selected_collection_ids` | `allow_collection_ids` | non-empty → **every** line must be in a listed collection | `collection_not_allowed` |
| `hide_vendors` | `deny_vendors` | line vendor (lower-case) **contains** an entry → deny | `vendor_not_allowed` |
| `show_vendors` | `allow_vendors` | non-empty → at least one line vendor equals an entry | `vendor_not_allowed` |
| `min_cart_total` / `max_cart_total` | `min_total_cents` / `max_total_cents` | a nil or non-positive bound is ignored; total = merchandise total after discounts | `total_out_of_range` |
| `phone_numbers` | `deny_phones` | buyer digits **contain** an entry | `phone_blocked` |
| `email_addresses` | `deny_emails` | buyer email **contains** an entry | `email_blocked` |
| `hide_gift_cards` | `hide_gift_cards` | any line with `"gift_card"=>true` → deny | `product_not_allowed` |

Plan independence: `RulesAdapter` reads the columns as stored, on every plan — the form applies Limit COD rules even on Free, where the checkout function runs in test mode (`lock_paid_feature`). `stage` behaviour: an address-dependent rule whose input is still empty is not a failure at `page`/`quote`; its name is added to `pending`. At `submit` an empty required input fails. `include_countries` on `Setting` is a post-order verification filter, not a COD rule — it is not used.

### E.4 `Visibility` (`visibility.rb`) — VIS-1..5

```ruby
Visibility.evaluate(general:, cart:, country:, page:)
# general = cod_form_shop_configs.general (B.1.1); page = "product"|"cart"|"drawer"|"quick_buy"|"api"|"embedded"
# => {"visible"=>true|false, "reasons"=>["country_not_enabled"|"page_disabled"|"product_excluded"|"product_not_included"|"order_total_out_of_range"|"out_of_stock"],
#     "message"=>general["order_total"]["message"] or nil}
```

`products.scope == "selected"`: every line must match `include_product_ids` or `include_collection_ids`. Exclude lists always apply (any matching line hides). `order_total` compares the cart merchandise total.

### E.5 `ShippingRates` (`shipping_rates.rb`) — SHP-1..6

```ruby
ShippingRates.select(rates:, cart:, address:, subtotal_cents:, currency:, selected_id:, free_shipping:)
# rates = [C.3 hashes]; cart = {"lines"=>[...], "total_quantity"=>Integer, "total_grams"=>Integer}
# => {"rates"=>[{"id","name","description","price_cents"}], "selected_id"=>Integer|nil,
#     "price_cents"=>Integer, "none_available"=>true|false, "pending_address"=>true|false}
```

- A rate qualifies when it is `active`, its `currency` is nil or equals `currency`, and every non-empty condition holds. A rate with a `countries`/`provinces` condition while the address has no country/province yet does **not** qualify, and `pending_address` is set to true (so the client shows "enter your address" rather than "no shipping available").
- Output order: `position`, then `price_cents`. `selected_id`: keep the caller's `selected_id` if it still qualifies, else the first rate (SHP-4/5).
- `free_shipping: true` (threshold offer reached or free-shipping discount code) sets every returned `price_cents` to 0.
- Only lines with `"requires_shipping"=>true` count towards weight and quantity. If no line requires shipping the result is `{"rates"=>[], "selected_id"=>nil, "price_cents"=>0, "none_available"=>false}`.

### E.6 `Offers` (`offers.rb`, `offer_overlap.rb`)

```ruby
Offers.match_quantity_offer(offers:, line:)                 # first active offer (by priority) targeting the line's product/collections → offer hash | nil
Offers.apply_quantity_tiers(lines:, offers:)                # => lines with "unit_discount_cents", "discount_title", "offer_id", "tier_index"
Offers.resolve_bumps(offers:, selected:, cart:, catalog:)   # selected = [{"offer_id","quantity"}] → extra line hashes (kind "bump")
Offers.apply_downsell(lines:, offer:)                       # adds per-unit discount on product lines, proportional to line totals
Offers.apply_discount_code(lines:, code:, subtotal_cents:, quantity:, stacking:)
#   code = normalised hash from CodForm::DiscountCodeService:
#     {"code","kind"=>"percentage"|"fixed_amount"|"free_shipping","value"=>Numeric,
#      "applies_to"=>{"all"=>true}|{"product_ids"=>[],"collection_ids"=>[]},
#      "min_subtotal_cents"=>nil,"min_quantity"=>nil}
#   => {"status"=>"applied"|"not_applicable"|"not_combinable"|"minimum_not_met", "amount_cents"=>Integer, "free_shipping"=>bool}
Offers.evaluate_thresholds(offers:, merchandise_total_cents:)  # => [{"offer_id","kind","threshold_cents","remaining_cents","reached"}]
OfferOverlap.conflicts(offers)                              # => [{"product_id","offer_ids"=>[..]}] among active quantity offers (OFF-2)
```

Tier discount per unit (cents), for unit price `p` and quantity `n`:
- `percentage v` → `Money.percent_of(p, v)`
- `unit_price v` → `max(p - v, 0)`
- `fixed_amount v` → `v / n` (integer division; the displayed and charged discount is `(v / n) * n`, so the buyer total always equals the order total — ORD-3)

Stacking order (OFF-8): quantity offer → downsell → discount code. Downsell percentage applies to the line totals **after** the quantity offer. The discount code applies to what remains; when `stacking["codes_combine_with_offers"]` is false and any quantity offer or downsell is applied, the code returns `not_combinable` and is not applied. Quantity offer and downsell become **per-unit line discounts**; the discount code becomes the single **order-level** discount.

### E.7 `Quote` (`quote.rb`) — the orchestrator used by session, quote and submit

```ruby
Quote.build(input) # => quote hash (D.2 "quote", plus internal keys listed below)
```

Input:

```ruby
{
  "currency" => "HUF",
  "stage" => "quote",                       # "page" | "quote" | "submit"
  "lines" => [                               # from CodForm::CatalogService
    {"key"=>"l0","variant_id"=>"44111","product_id"=>"8111","collection_ids"=>["301"],"vendor"=>"Acme",
     "title"=>"Widget","variant_title"=>"Blue","image"=>"https://…","quantity"=>3,
     "unit_price_cents"=>199900,"compare_at_cents"=>249900,"grams"=>500,
     "requires_shipping"=>true,"taxable"=>true,"gift_card"=>false,
     "available"=>true,"inventory_quantity"=>10,"inventory_policy"=>"deny","properties"=>{}}
  ],
  "address" => {"country"=>"HU","province"=>"BU","city"=>"Budapest","zip"=>"1051"},
  "contact" => {"phone_digits"=>"36301234567","phone_national"=>"301234567","email"=>"anna@example.com"},
  "general" => { B.1.1 },
  "fraud" => { B.1.2 },
  "rules" => { E.3 rules },
  "shipping_rates" => [ C.3 ],
  "selected_shipping_rate_id" => 4,
  "offers" => {"quantity"=>[...], "bumps"=>[...], "downsell"=>{...}|nil, "thresholds"=>[...]},   # already filtered by gates, schedule and A/B
  "selected_bumps" => [{"offer_id"=>21,"quantity"=>1}],
  "bump_catalog" => {"44999"=>{ line hash for variant bumps }},
  "discount_code" => nil | { normalised code hash } | {"code"=>"X","error"=>"not_found"},
  "cod_fee" => {"enabled"=>true,"mode"=>"fixed"|"percentage","value"=>500.0,"label"=>"Cash on delivery fee","taxable"=>false,"fx_rate"=>1.0},
  "tax" => {"prices_include_tax"=>true, "calculated"=>nil | {"amount_cents"=>…, "lines"=>[…]}},
  "partial_rules" => [ E.11 rule hashes ],
  "risk" => nil | {"band"=>"high","score"=>81},
  "otp" => {"shop_enabled"=>true, "mode"=>"before_order", "risk_band"=>"medium", "verified"=>false},
  "block" => {"blocked"=>false, "reason"=>nil},          # from Fraud.check, computed by the adapter
  "is_test" => false
}
```

Steps, in order: (1) availability and `max_quantity` per line; (2) `Offers.apply_quantity_tiers`; (3) `Offers.apply_downsell`; (4) bumps and free-gift lines; (5) `Offers.apply_discount_code`; (6) thresholds; (7) `Visibility` + `CodRules` + `block` + RTO gating → `eligibility`; (8) `ShippingRates.select`; (9) `CodFee.compute`; (10) tax; (11) totals; (12) `PartialRules.options` → `payment_options`; (13) `OtpPolicy.required?` → `otp_required`.

Extra internal keys in the output (not sent to the browser; `CodForm::QuoteService` strips keys starting with `_`): `"_draft"` (the inputs `DraftOrderBuilder` needs: per-line `unit_discount_cents`, order-level discount, shipping title/price, fee line), `"_fingerprint"` (SHA-256 of the canonical JSON of lines, discounts, shipping, fee and total — used to detect a change between quote and submit).

RTO gating (RUL-3): when `general["rto"]["gating_enabled"]` and `risk["band"]` rank ≥ `block_band` (or `score ≥ min_score`): `eligibility.cod_allowed = false`, reason `rto_high_risk`, message = `general["rto"]["message"]`; `payment_options` then contains only `partial` / `prepaid` options (no `cod`), and `pay_online` is true.

### E.8 `CodFee` (`cod_fee.rb`) — FEE-1, FEE-2

```ruby
CodFee.compute(config:, base_cents:)
# config = {"enabled"=>true,"mode"=>"fixed"|"percentage","value"=>Numeric,"label"=>String,"taxable"=>false,"fx_rate"=>Float}
# => {"enabled"=>true,"label"=>"…","amount_cents"=>Integer,"taxable"=>false}
```

- Source (adapter `CodForm::CodFeeAdapter.from_setting(setting, currency:, shop_currency:)`): `cod_fee_enabled`, `cod_fees`, `is_percentage`, `cod_label`. `taxable` comes from `general` (`"cod_fee_taxable"`, default false).
- `fixed`: `(value * 100 * fx_rate).round`; `fx_rate` is 1.0 when the quote currency is the shop currency, else `ExchangeRateBank` shop→presentment (rounded to the unit for currencies conventionally shown without decimals: HUF, COP, RSD, PKR, JPY, KRW, CLP).
- `percentage`: `Money.round_to_half_unit(Money.percent_of(base_cents, value))` — same rounding as F5. `base_cents` = merchandise total after discounts + shipping.
- Disabled or zero → `amount_cents: 0`, `enabled: false`.
- This is the **only** fee on form orders, on every plan (Free included). The amount of a COD-type `PartialRuleSet` is ignored by the form (Express keeps using it). Label = `Setting#cod_label`, or "Cash on delivery fee" when blank.

### E.9 `Fraud` (`fraud.rb`) — FRD-1..4

```ruby
Fraud.check(fraud:, entries:, counts:, contact:, ip:, cart:, timing:, is_test:)
# entries = {"phone"=>["36301234567", ...], "email"=>["a@b.c","*@x.com"], "ip"=>["1.2.3.4","10.0.0.0/8"]}   (only candidates the adapter pre-filtered)
# counts  = {"phone"=>2, "email"=>0, "ip"=>7}        orders by this phone/email/ip inside each configured window (adapter queries cod_form_sessions)
# timing  = {"elapsed_ms"=>48211, "token_age_ms"=>52000, "honeypot_value"=>""}
# => {"ok"=>true|false, "code"=>nil|"blocked"|"limit_reached"|"bot_suspected",
#     "reason"=>nil|"phone_blocked"|"email_blocked"|"ip_blocked"|"phone_limit"|"email_limit"|"ip_limit"|"max_quantity"|"honeypot"|"too_fast",
#     "message"=>String|nil}
```

`is_test: true` (FRD-5) skips block lists and limits but not `max_quantity`. `too_fast`: `min(elapsed_ms, token_age_ms) < min_submit_seconds * 1000`. Helper `Fraud.mask(kind, value)` produces the masked subject for `cod_form_rejections`.

### E.10 `Phone` and `CountrySchema` (`phone.rb`, `country_schema.rb`) — FRM-5, FRM-7

Data file: `config/cod_form/countries.json` (owner WS2), one entry per ISO2 country; countries without an entry use the `"default"` entry.

```json
{
  "HU": {"dial_code": "36", "phone": {"min": 8, "max": 9, "strip_leading_zero": true, "mobile_prefixes": ["20","30","31","50","70"], "enforce_mobile": false},
         "address": {"province": {"mode": "hidden"}, "city": {"mode": "free"}, "zip": {"required": true, "regex": "^[0-9]{4}$", "label_key": "label_zip"}}},
  "IN": {"dial_code": "91", "phone": {"min": 10, "max": 10, "strip_leading_zero": true, "mobile_prefixes": ["6","7","8","9"], "enforce_mobile": true},
         "address": {"province": {"mode": "select", "required": true}, "city": {"mode": "free"}, "zip": {"required": true, "regex": "^[1-9][0-9]{5}$", "label_key": "label_pincode", "lookup": true}}},
  "default": {"dial_code": "", "phone": {"min": 6, "max": 14, "strip_leading_zero": false, "mobile_prefixes": [], "enforce_mobile": false},
              "address": {"province": {"mode": "auto"}, "city": {"mode": "free"}, "zip": {"required": false, "regex": "", "label_key": "label_zip"}}}
}
```

`province.mode`: `hidden`, `select` (list from D.11), `auto` (select when the geo endpoint returns provinces, else hidden). `city.mode`: `free`, `select`. `zip.lookup: true` → the client calls the postal endpoint and fills city and province (FRM-6). The file must contain at least: HU, CO, RS, DO, MA, PE, PK, IN, plus `default`.

```ruby
Phone.validate(raw:, country:, rules:)
# rules = the country's "phone" hash + "dial_code"
# => {"valid"=>true|false, "national"=>"301234567", "e164"=>"+36301234567", "digits"=>"36301234567", "error"=>nil|"too_short"|"too_long"|"bad_prefix"|"empty"}
CountrySchema.for(country:, data:)          # => merged schema hash for one country (the "default" entry filled in)
```

Normalisation: remove everything but digits and a leading `+`; a leading `+<dial>` or `00<dial>` or `<dial>` (only when the remaining length is still within min..max) is stripped; then leading zeros are stripped when `strip_leading_zero`. `Phonelib` is **not** used here (pure Ruby); `CodForm::OrderService` may additionally call `Phonelib.valid_for_country?` as a soft check that only logs.

### E.11 `PartialRules` (`partial_rules.rb`) — PRE-4, PRE-7..9

```ruby
PartialRules.match(rules:, cart:, address:, contact:, risk:)       # => [rule hashes that apply], in position order
PartialRules.options(rules:, totals:, cod_allowed:, money_format:) # => D.2 "payment_options" hash | nil
PartialRules.amounts(rule:, totals:)                               # => {"pay_now_cents","pay_later_cents","discount_cents"}
PartialRules.handoff_attributes(rule:, cart:, session:, dummy_variant_id:, otp_phone_e164:, country:) # => {"cart_attributes"=>{…D.8…}, "discount_code"=>String|nil}
```

Rule hash = `PartialRuleSet#as_json` with string keys, produced by `CodForm::PartialRulesAdapter.for(shop)` (`shop.partial_rule_sets.where(is_enabled: true)`, only when `Setting#partial_payment_enabled`). Matching, per rule (all must hold):

| Field(s) | Condition |
| --- | --- |
| `min_cart_range`, `max_cart_range` | when > 0: merchandise total (decimal) within range |
| `product_scope`, `product_ids`, `match_any_product` | `all` → pass; `include` → every line's product in list (any, when `match_any_product`); `exclude` → none in list |
| `variant_scope`, `variant_ids` | same logic as `PartialRuleSet#variant_matches?` |
| `collection_scope`, `collection_ids` | same logic as `PartialRuleSet#collection_matches?` |
| `cart_items_range` | `min_cart_items` / `max_cart_items` against total quantity |
| `zipcode_blacklist_enabled` + `zipcode_blacklist`, `zipcode_whitelist_enabled` + `zipcode_whitelist` | same as `zipcode_blacklisted?` / `zipcode_whitelisted?`; skipped while the zip is empty |
| `rto_engine` | hidden when `enabled` and band rank ≥ `hide_at_band` or `score ≥ min_score` (same as `rto_engine_hides?`) |
| `phone_blacklist`, `email_blacklist` | array of strings; rule hidden when the buyer's phone digits / email is listed |

`options`:
- `kind` per rule: `amount_type == "cod"` → `cod`; `amount_type == "percentage"` and `amount == 100` → `prepaid`; otherwise `partial`.
- The step exists (non-nil result) only when at least one matching rule is `partial` or `prepaid` (PRE-8).
- The `cod` option is always listed first and is the `default_id` when `cod_allowed` is true (it is the form's own full-COD path, `rule_id` nil, fee from E.8 — never from a rule); it is omitted only when RTO gating or a COD rule removed COD. Matching COD-type rules produce no extra option.
- `amounts`: `fixed` → `pay_now = min(amount, total)`; `percentage` → `Money.percent_of(base, amount)` where base = merchandise total before order-level discounts (same base as `calculatePaymentAmounts` in `bundlePaymentUtils.js:345-440`); rule discount (`discount_value`, `discount_type`, only when `discount_code` is present): percentage of (original total − line-level discounts) or fixed. `pay_later = total − discount − pay_now` (never negative).
- `description`: `sub_heading` when present, else `description_template` or the default template of `PartialRuleSet::DEFAULT_TEMPLATES`, with `{{pay_now}} {{pay_later}} {{total}} {{discount}} {{cod_fee}}` replaced by `Money.format(cents, money_format)` strings.

`handoff_attributes` reproduces `buildCartAttributes` (`bundlePaymentUtils.js:443-538`) and `handleSimpleFlow` (`partialPaymentUtils.js:292-385`); see G.9 for the attribute list.

### E.12 `SessionToken` (`session_token.rb`) — FRD-4, NFR-6

```ruby
SessionToken.issue(secret:, shop_id:, session_id:, issued_at:, ttl_seconds: 7200, test: false)  # => "v1.<b64url(payload)>.<b64url(sig)>"
SessionToken.verify(secret:, token:, now:)
# => {"ok"=>true,"shop_id"=>Integer,"session_id"=>String,"issued_at"=>Integer,"expires_at"=>Integer,"test"=>bool}
#  | {"ok"=>false,"error"=>"malformed"|"bad_signature"|"expired"}
```

Payload JSON keys: `sid`, `shp`, `iat`, `exp`, `t`. Signature: `OpenSSL::HMAC.digest("SHA256", secret, "v1." + b64url(payload))`, compared in constant time (`OpenSSL.fixed_length_secure_compare` after a length check). `secret`, `issued_at`, `now` are passed in (integers, epoch seconds).

### E.13 Config classes

| Class (file) | Methods | Notes |
| --- | --- | --- |
| `Defaults` (`defaults.rb`) | `form_config`, `button_config`, `general`, `fraud`, `templates`, `feature_gates`, `plan_limits` | Country-neutral. `button_config` = preset B. |
| `FormConfig` (`form_config.rb`) | `normalize(raw) → {"config"=>…, "errors"=>[{"path","code"}], "warnings"=>[…]}`, `for_storefront(config, locale:) → config with texts reduced to locale + en` | Enforces C.2 rules. |
| `FormValidator` (`form_validator.rb`) | `validate(config:, schema:, values:) → {"valid"=>bool, "fields"=>{"zip"=>"error_zip"}}` | Server-side twin of the client validation (required, lengths, regex, email format, latin-only, phone via `Phone`). |
| `FormTargeting` (`form_targeting.rb`) | `pick(forms:, cart:, requested_id:) → form hash` | First active non-default form (by `position`) whose targeting matches any cart line; else the default. `requested_id` wins only for test sessions. |
| `ButtonConfig` (`button_config.rb`) | `normalize(preset:, config:) → {"preset","config","errors"}` | Colours must match `^#[0-9a-fA-F]{6}$`; selectors max 200 chars, no `<`, `>`, `{`, `}`. |
| `MetafieldPayload` (`metafield_payload.rb`) | `build(input) → C.1 hash` | `input = {"enabled","api","shop","version","general","button":{preset,config},"rules","quantity_offers","features","cap_fallback","test_only"}` |
| `FeatureGates` (`feature_gates.rb`) | `allowed?(feature_key:, tier:, gates:, overrides:) → bool`, `map(tier:, gates:, overrides:) → {"key"=>{"allowed","min_tier"}}` | Tier order `free < pro < enterprise < enterprise_plus`. Override wins; an unknown key is denied. |
| `CapResolver` (`cap_resolver.rb`) | `resolve(limits:, shop_id:, tier:, country_group_ids:, global:) → {"cap"=>Integer\|nil,"behaviour","grace_orders","overage_rate","source"}`; `state(resolved:, orders_count:) → {"state"=>"ok"\|"grace"\|"flagged"\|"fallback","over_by"=>Integer,"percent"=>Integer\|nil}` | Order: shop → country group (tier-specific row, then tier-less row, groups in `position` order) → plan. `behaviour` and `grace_orders` inherit separately down the same chain, finally `global`. Inactive rows are ignored. A matching row with `monthly_cap` nil means unlimited and stops the search (CAP-3). |
| `OtpPolicy` (`otp_policy.rb`) | `required?(shop_enabled:, mode:, risk_band:, target_band:, verified:) → bool` | `before_order` → required unless verified; `order_first` → false (order is created, tag added on later verification); `risk_based` → required only when the band rank ≥ `target_band` (default `medium`). Never required when `shop_enabled` is false. |
| `AbTest` (`ab_test.rb`) | `assign(test:, seed:) → variant key` | Deterministic: `Digest::SHA256.hexdigest("#{test['id']}:#{seed}")[0, 8].to_i(16) % 100` against cumulative weights; `seed` = `client_id`. |
| `ThankYou` (`thank_you.rb`) | `resolve(config:, locale:, order:, contact:) → {"type","url","message","whatsapp_url"}` | Substitutes the variables of C.2. |
| `DraftOrderBuilder` (`draft_order_builder.rb`) | `build(quote:, contact:, address:, meta:) → DraftOrderInput hash (symbol-free, camelCase string keys)` | F.3. |
| `Recovery` (`recovery.rb`) | `url(primary_domain:, token:) → String`, `prefill(session:) → hash` | ABN-2. |

---

## F. Order creation

### F.1 Rails services (AR-backed adapters) — `app/services/cod_form/`

| Class (file) | Responsibility | Owner |
| --- | --- | --- |
| `CodForm::Availability` (`availability.rb`) | `call(shop) → {available:, fallback:}`: kill switch, `module_access`, `storefront_mode`, gate `cod_form_core`. | WS3 |
| `CodForm::OriginGuard` (`origin_guard.rb`) | D.0.2. | WS3 |
| `CodForm::RateLimiter` (`rate_limiter.rb`) | `hit!(key, limit:, period:) → bool` on `Rails.cache`. | WS3 |
| `CodForm::CatalogService` (`catalog_service.rb`) | `lines(shop, items, country:) → [E.7 line hashes]`. One Admin GraphQL `nodes(ids:)` call for `ProductVariant` (`price`, `compareAtPrice`, `contextualPricing(context: {country: $country}) { price { amount currencyCode } compareAtPrice { amount } }`, `availableForSale`, `inventoryQuantity`, `inventoryPolicy`, `taxable`, `image`, `inventoryItem { requiresShipping measurement { weight { value unit } } }`, `product { id title vendor isGiftCard featuredImage { url } collections(first: 50) { nodes { id } } }`). Cached per variant + country for 60 s (`codf:var:<shop_id>:<variant_id>:<country>`). Also `shop_info(shop) → {"currency","taxes_included","money_format"}` cached 1 h. Unknown variant → raises `CodForm::Errors::InvalidItem`. | WS3 |
| `CodForm::RulesAdapter`, `CodFeeAdapter`, `PartialRulesAdapter`, `MoneyFormatAdapter` (`adapters/*.rb`) | `Setting` / `PartialRuleSet` / `Shop` → engine hashes. | WS3 |
| `CodForm::OfferResolver` (`offer_resolver.rb`) | Loads active offers for the cart, applies gates, schedule, and A/B assignment (`Engine::AbTest`), returns the `"offers"` input of E.7 and the session `ab_assignments`. | WS3 |
| `CodForm::DiscountCodeService` (`discount_code_service.rb`) | `lookup(shop, code) →` normalised hash of E.6 or `{"code","error"}`. Admin GraphQL `codeDiscountNodeByCode(code:)`; supports `DiscountCodeBasic` (percentage / fixed amount, all items or specific products/collections, minimum subtotal or quantity, active dates, usage limit not exhausted) and `DiscountCodeFreeShipping`; everything else → `error: "unsupported"`. Cached 60 s. | WS3 |
| `CodForm::RiskService` (`risk_service.rb`) | Wraps `Rto::DecisionService` (F18); returns `{"band","score"}`; never raises (nil on error). Called only when RTO gating or risk-based OTP is on and the gate allows it, and only once phone + zip are present. | WS3 |
| `CodForm::FraudAdapter` (`fraud_adapter.rb`) | Builds `entries` and `counts` for `Engine::Fraud` (indexed queries on `cod_block_entries` and `cod_form_sessions`). Writes `CodForm::Rejection`. | WS3 |
| `CodForm::QuoteService` (`quote_service.rb`) | `call(shop:, config:, session:, params:, stage:) → quote`. Assembles the E.7 input, calls `Engine::Quote.build`, calls `TaxService` when needed, stores the snapshot. | WS3 |
| `CodForm::TaxService` (`tax_service.rb`) | `calculate(shop, draft_input) → {"amount_cents","lines","total_cents"}` using GraphQL `draftOrderCalculate` with **the same input** `DraftOrderBuilder` produces (so quote and order agree — ORD-3). Cached 10 min by fingerprint + address. The existing `ShopifyServices::DraftOrderCalculateService` is not changed. | WS3 |
| `CodForm::CapService` (`cap_service.rb`) | `state(shop) → {"state","cap","orders","behaviour","percent"}` (cached 30 s), `period_for(shop, time)` (F28), `record_order!(shop, session, partial:)`. Loads `PlanLimit` rows + `CountryGroup`s and calls `Engine::CapResolver`. | WS3 |
| `CodForm::CustomerResolver` (`customer_resolver.rb`) | ORD-6: find by phone (`customers(first: 1, query: "phone:+36…")`), then by email, else `customerCreate`; returns the customer gid or nil. Never writes a placeholder email. Failures are swallowed (Shopify then matches by email/phone itself). | WS3 |
| `CodForm::OtpService` (`otp_service.rb`) | D.4 / D.5. | WS3 |
| `CodForm::OrderService` (`order_service.rb`) | F.2. | WS3 |
| `CodForm::HandoffService` (`handoff_service.rb`) | D.8. | WS3 |
| `CodForm::UpsellService` (`upsell_service.rb`) + `ShopifyServices::OrderEditAddLineService` (`app/services/shopify_services/order_edit_add_line_service.rb`) | F.6. | WS3 |
| `CodForm::OrderWebhookHook` (`order_webhook_hook.rb`) | F.5. | WS3 |
| `CodForm::EnableService`, `MetafieldSyncService`, `EmbedStatusService`, `DomainSyncService`, `MerchantAudit` (`enable_service.rb`, …) | Admin-side services (H, C.1). `EmbedStatusService` reads `config/settings_data.json` of the main theme like `ShopifyServices::ShopifyAssetService` but matches block types ending in `/blocks/cod-form-embed/<uid>` (new embed) and `/blocks/app-embed/<uid>` (legacy) separately — the existing `is_cod_king_block_enabled?` matches any block of the app and cannot tell them apart. | WS6 |

### F.2 `CodForm::OrderService.call(shop:, config:, session:, params:, request_meta:)`

1. **Compare-and-set.** One SQL statement:
   `UPDATE cod_form_sessions SET status = 'ordering', idempotency_key = :key, updated_at = now() WHERE id = :id AND order_id IS NULL AND status IN ('open','otp_pending','blocked','abandoned','recovered')`.
   0 rows → reload: `order_id` present → return the stored order (HTTP 200, ORD-4); `status == 'ordering'` → 409 `already_processing`; otherwise 409 `already_processing`.
   Any failure after this point resets `status` to `'open'` and stores `order_error` (ensure block), so the buyer can retry.
2. **Bot checks** (FRD-4): `Engine::Fraud.check` with `elapsed_ms`, token age (now − `iat`), honeypot value.
3. **Validation**: `Engine::FormValidator.validate` on `contact`, `address`, `fields`, `custom_fields` with the session's published form config → 422 `validation_failed`.
4. **Fraud**: block lists and velocity counts → 422 `blocked` / `limit_reached` (+ `CodForm::Rejection`).
5. **Cap**: `CapService.state` → 409 `cap_reached` when `fallback` (CAP-6). Test sessions skip this, the velocity limits and block lists (FRD-5).
6. **Re-quote** with `stage: "submit"` from fresh catalog data (ORD-2). `eligibility.cod_allowed == false` → 422 `not_eligible`; `shipping.none_available` → 422 `no_shipping_rate`; a line with `available == false` or quantity > `max_quantity` → 422 `out_of_stock`; discount code status ≠ `applied` when a code was sent → 422 `discount_invalid`.
7. **OTP**: `quote["otp_required"]` and (`session.otp_verified_at` nil or verified phone ≠ submitted phone) → 428 `otp_required` — unless `session.otp["bypassed"]` is true (D.4), in which case the order proceeds unverified.
8. **Payment option**: when `quote["payment_options"]` is present, `payment_option_id` must be `"cod"`; a partial/prepaid id → 400 `invalid_request` (those go through `/api/form/handoff`).
9. **Tax**: when `quote["tax"]["required"]`, `TaxService.calculate`.
10. **Total check**: `quote["total_cents"] != expected_total_cents` → 409 `total_changed` with the new quote.
11. **Customer**: `CustomerResolver`.
12. **Create**: `ShopifyServices::CodOrderCreateService.call(shop, {}, {}, {}, nil, nil, verified, form_context: {...})` (F.4). After `draftOrderCreate`, the draft's `totalPriceSet.presentmentMoney.amount` is compared with `quote["total_cents"]`; a difference above `max(2, lines.size)` cents deletes the draft (`draftOrderDelete`) and returns 409 `total_changed` with a quote whose totals are taken from Shopify; a smaller difference is accepted and logged as `total_drift_cents`.
13. **Persist**: session `status = 'ordered'`, `order_id`, `order_name`, `order_total_cents`, `ordered_at`, `contact`, `address`, `phone_normalized`, `email_normalized`, `ip`.
14. **Usage** (CAP-1/2): `CapService.record_order!` unless `is_test` (test orders increment `test_orders_count`). When the new count crosses a notice threshold or the cap: `CodForm::CapNotifyJob.perform_async(shop.id, period)` and `MetafieldSyncJob` (to set `cap_fallback`).
15. **Events**: `FormFunnelEvent` `cf_order_created` (server-written), then `CodForm::PostOrderJob.perform_async(session.id)` (I.3).
16. **Upsell**: pick the active upsell offer for the cart (gate `upsell`), store `session.upsell = {"offer_id", "expires_at"}`.
17. **Response**: D.6, with `Engine::ThankYou.resolve`.

Timeouts: Shopify HTTP read timeout 12 s. With `async_orders` on, steps 11–17 run in `CodForm::CreateOrderJob` (queue `critical`); the controller polls the session row every 250 ms for up to 8 s, then answers 202 (ORD-9). With it off (default, "no queue in P1") everything is inline.

### F.3 Draft order built by `CodForm::Engine::DraftOrderBuilder.build(quote:, contact:, address:, meta:)`

`meta = {"shop_tags"=>[], "verified"=>bool, "verification_tag"=>String, "session_id"=>String, "form_id"=>Integer, "is_test"=>bool, "attribution"=>{}, "custom_fields"=>[{"label","value"}], "customer_gid"=>String|nil, "note_fields"=>{"gst_number"=>"", "note"=>""}, "otp_phone_e164"=>String|nil, "country"=>"HU"}`

Output (GraphQL `DraftOrderInput`, API 2025-07):

```ruby
{
  "lineItems" => [
    # product line (quantity offer and/or downsell as a per-unit discount)
    {"variantId" => "gid://shopify/ProductVariant/44111", "quantity" => 3,
     "appliedDiscount" => {"valueType" => "FIXED_AMOUNT", "value" => 500.0, "title" => "3 packs", "description" => "3 packs"},
     "customAttributes" => [{"key" => "Engraving", "value" => "Anna"}]},
    # variant bump: same shape, plus {"key" => "_codk_line", "value" => "bump:21"}
    # custom bump (OFF-5)
    {"title" => "Express handling", "quantity" => 1,
     "originalUnitPriceWithCurrency" => {"amount" => "499.00", "currencyCode" => "HUF"},
     "requiresShipping" => false, "taxable" => true,
     "customAttributes" => [{"key" => "_codk_line", "value" => "bump:21"}]},
    # free gift (OFF-11): variant line with appliedDiscount PERCENTAGE 100, {"_codk_line" => "gift:40"}
    # COD fee (FEE-1): its own custom line, title = Setting#cod_label
    {"title" => "Cash on delivery fee", "quantity" => 1,
     "originalUnitPriceWithCurrency" => {"amount" => "500.00", "currencyCode" => "HUF"},
     "requiresShipping" => false, "taxable" => false,
     "customAttributes" => [{"key" => "_codk_line", "value" => "cod_fee"}]}
  ],
  "appliedDiscount" => {"valueType" => "FIXED_AMOUNT", "value" => 499.6, "title" => "WELCOME10", "description" => "Discount code WELCOME10"},  # discount code only; omitted otherwise
  "shippingLine" => {"title" => "Standard delivery", "priceWithCurrency" => {"amount" => "1490.00", "currencyCode" => "HUF"}},               # omitted when no line requires shipping
  "shippingAddress" => {"firstName","lastName","address1","address2","city","provinceCode","countryCode","zip","phone"},
  "billingAddress" => (same),
  "email" => "anna@example.com",        # nil when the buyer gave none — never a placeholder (ORD-6)
  "phone" => "+36301234567",
  "purchasingEntity" => {"customerId" => "gid://shopify/Customer/…"},   # omitted when unresolved
  "presentmentCurrencyCode" => "HUF",   # PRE-5
  "taxExempt" => false,
  "note" => "COD Form order\nNote: …\nGST: …",
  "tags" => ["COD", "Created-From-COD-King", "codking_form", "✅ COD-Verified"],
  "customAttributes" => [
    {"key" => "_codkFormSessionId", "value" => "0b6c9c2e-…"},
    {"key" => "_codkFormId", "value" => "5"},
    {"key" => "_codkCodFee", "value" => "500.00"},
    {"key" => "_codkSessionId", "value" => "0b6c9c2e-…"},
    {"key" => "_otpVerifiedPhoneNumber", "value" => "+36301234567"},   # only when OTP verified
    {"key" => "_codkCountryCode", "value" => "HU"},
    {"key" => "_codk_campaign_json", "value" => "{\"utm_source\":\"fb\"}"},   # CampaignAttributionHelper format (ORD-5, TRK-4)
    {"key" => "Delivery note", "value" => "Leave at the door"}                # custom fields, visible "additional details" (FRM-13)
  ]
}
```

Notes:
- **COD fee representation.** For checkout orders the fee is a line item added by order edit (F5); for Express it is hidden in the shipping line (F4). The form uses a dedicated **custom line item** titled with `Setting#cod_label`: it is a line like the checkout representation, it is its own line in totals (FEE-1), it supports the taxable option (`general.cod_fee_taxable`, default off — FEE-2), and it needs no product. Quantity 1, `requiresShipping: false`, never merged into the shipping line; no "COD-Fees" product variant and no `CodFeesService` run on form orders (F.5). The legacy Express representation is unchanged.
- Tags: `"COD"` and `"Created-From-COD-King"` are kept from the existing service; `codking_form` added (ORD-5); the verification tag when verified (OTP-3); `codking_form_test` for test sessions.
- `_otpVerifiedPhoneNumber` + `_codkSessionId` route a verified order into the existing verified branch of the webhook job (F8); `PreOrderOtp.device_id` equals the session `public_id` because `OtpService` sent it as `device_id`.
- Quantity-offer discounts on percentage tiers use `"valueType" => "PERCENTAGE"`; all others `FIXED_AMOUNT` per unit.
- OFF-9: line `properties` from the cart are passed through as `customAttributes` on the line unchanged; lines whose properties contain bundle-app keys (any key starting with `_` or `__`) are never given a quantity-offer discount and keep the price the server reads for the variant. Bundle prices that exist only in the storefront cart (cart-transform bundles) cannot be reproduced by a draft order — for such carts the session returns `fallback: "bundle_cart"` (detection rule in D.1); the button stays visible and the tap opens Shopify checkout.

### F.4 Change to `ShopifyServices::CodOrderCreateService` — owner WS3, backward compatible

- New keyword `form_context: nil` on `initialize` and `self.call` (default nil → every existing call site behaves exactly as today).
- `form_context` keys: `:draft_input` (hash from F.3), `:expected_total_cents`, `:tolerance_cents`.
- In `create_draft_order`: `variables = { input: form_context ? form_context[:draft_input] : <legacy hash> }`. The mutation selection adds `totalPriceSet { presentmentMoney { amount currencyCode } }`.
- In `call`: with any `form_context`, `report_purchase_to_meta_if_configured` returns without sending (the pixel job does it, I.3). Return hash gains `draft_total_cents`, `draft_order_id`, and on error `code:` (`"draft_user_errors"`, `"complete_failed"`, `"total_changed"`, `"exception"`).
- **PII removal (NFR-7), applied to both paths:** delete the `variables.inspect` / `resp.inspect` log lines (248, 250), the shipping debug lines (341-343, 359, 382-383, 393); log `shop.id`, draft id, order id, line count and total only. Replace the per-order **success** Slack post (lines 125-131) with nothing; keep the failure posts but drop `Payload:` (lines 118-123, 136-140 keep shop, order id, error).
- The `@shipping_rate_details` defect (F3) is **not** fixed in this project (product decision 1): with `form_context` nil the service must build a byte-identical draft order to today's. Form orders get their shipping line only through `form_context`. The fix is a separate ticket with a merchant announcement.

### F.5 Webhook side: keeping existing messaging (ORD-8) — `CodForm::OrderWebhookHook`, two small edits in `app/workers/order_confirmation_create_job.rb` (owner WS3)

What triggers messaging today is F7–F10. A form order is a draft order completed with payment pending, so `is_cod` is true (F10), **but** F9 would suppress all messages (default `skip_draft_order = true`) or add the COD fee twice. The fix:

```ruby
# 1) in #perform, directly after `shop = Shop.find(shop_id)`:
params = CodForm::OrderWebhookHook.normalize(params)
#    If note attribute `_codkFormSessionId` is present AND the order was created by the form
#    (session.order_id == params['id'].to_s): sets params['source_name'] = 'codking_form'
#    and params['_codk_form'] = true. Otherwise returns params unchanged.

# 2) in #create_order, the CodFeesService condition (line 379) gains:  && !params['_codk_form']

# 3) at the end of #perform (after release_lock, in an ensure-safe begin/rescue):
CodForm::OrderWebhookHook.after(shop, params)
```

Effects:
- Because every existing check compares `source_name` with `'shopify_draft_order'` (lines 375, 379, 483, 679-683, 735), a form order now takes exactly the path of a checkout COD order: post-order verification, confirmation SMS/WhatsApp, BSP `cod_verification`, first-purchase, COD-to-prepaid reminders, and later fulfilment messages (those key on the `OrderConfirmation`, which now exists).
- The fee is not added a second time.
- Scope: only orders whose `_codkFormSessionId` matches a session whose `order_id` is that order. Every other draft order behaves exactly as today. Test orders (`codking_form_test`) go through the same messaging, so the merchant sees the full flow.
- A form order that was not OTP-verified (OTP off, or bypassed per D.4) gets the shop's post-order verification like a checkout COD order; a verified one takes the verified branch and gets no second verification.
- OTP-verified form orders go through the verified branch (F8) like verified Express/checkout orders.
- `OrderWebhookHook.after`: (a) sets `OrderConfirmation#cod_fee` from `_codkCodFee`; (b) marks abandoned-cart anchors `codf_<session_id>` as `Recovered`; (c) **partial / prepaid orders that started in the form** (note attribute `_codkFormSessionId` present, session `status` in `handoff_partial`, `handoff_prepaid`): for `handoff_partial` adds tags `codking_form` and `codking_form_partial` (`ShopifyServices::OrderTagPostService`), calls `CapService.record_order!(partial: true)` and writes `cf_order_created` with `meta.partial = true` (PRE-10, CAP-1); for `handoff_prepaid` writes `cf_prepaid_order` only (not counted, CAP-1). Both set the session to `ordered`. All of (c) is idempotent on `session.order_id`.

Other existing flows that keep working without change: `AbandonedCartStatusUpdateJob` (runs for every created order), RTO ingestion (`Rto::WebhookIngestService`), `Whatsapp::ContactBook`.

### F.6 One-click upsell (OFF-10) — `CodForm::UpsellService.accept(session:, offer_id:)`

1. `session.upsell["offer_id"] == offer_id`, now < `expires_at`, `accepted_at` nil; else 410.
2. `ShopifyServices::OrderEditAddLineService.call(shop, order_id:, variant_id:, quantity:, discount:)`: `orderEditBegin` → `orderEditAddVariant(id:, variantId:, quantity:, allowDuplicates: true)` → `orderEditAddLineItemDiscount(id:, lineItemId:, discount: {percentValue: …} | {fixedValue: {amount:, currencyCode:}, description: "Upsell"})` → `orderEditCommit(id:, notifyCustomer: false, staffNote: "COD King upsell")`. The existing `OrderEditService` (COD fee) is not touched.
3. Tag `codking_upsell`; session `upsell.accepted_at`, `order_total_cents` updated; funnel event `cf_upsell_accept`; `CodForm::Tracking::ServerDispatchJob` sends nothing extra (the Purchase event value stays the original total; decision 10: messaging and events already sent are not corrected).
4. The COD fee is **not** recomputed for a percentage fee after an upsell.

### F.7 OTP "order first" mode (OTP-6)

With `general.otp.mode == "order_first"`: the order is created without the verification tag; the response adds `"otp": {"pending": true}`; the form shows the OTP step after the thank-you transition; on successful `/api/form/otp/verify` for an `ordered` session, `OtpService` adds the verification tag with `ShopifyServices::OrderTagPostService` and updates the `OrderConfirmation` to `COD-Verified`.

---

## G. Storefront package

### G.1 Layout — `payment-customization-js/storefront/cod-form/`

```
storefront/cod-form/
  package.json                 private; devDependencies: esbuild, preact (^10.29, same range as the repo root), @playwright/test (optional e2e)
  build.mjs                    esbuild build + clean + size check (G.11)
  size-limits.json             gzip budgets per output file (G.10)
  README.md                    build / dev / harness / page-builder hooks (BTN-10: GemPages, PageFly, Zipify)
  scripts/export-texts.mjs     writes ../../../cod-confirm/config/cod_form/default_texts.json from src/i18n/*.json
  src/
    shared/
      selectors.js             BUY_NOW, CART_DRAWER, CART_CHECKOUT, ADD_TO_CART, WALLETS (copied from app-embed.liquid:408-470, not imported)
      money.js                 formatMoney(cents, moneyFormat)
      dom.js                   qs, qsa, on, ready
      storage.js               safe localStorage / sessionStorage get, set
      events.js                emit(name, detail) (DOM CustomEvents), track(type, meta) + flush() (funnel queue → /api/form/events)
      attribution.js           collect() → {attribution, tracking}
      consent.js               getConsent()
      cart.js                  getCart(), addItems(items), updateCart(body), clearCart()
      fallback.js              goToCheckout(ctx)
    loader/                    plain JS → codk-form-loader.js (IIFE)                         [WS4]
      index.js                 boot
      config.js                reads window.__CODKF__, resolves locale labels
      product.js               variant / quantity / properties reader, variant-change watcher
      button.js                COD button, {total} label
      visibility.js            client-side VIS / rules checks that Liquid cannot do (variant-level, cart total)
      open.js                  intent prefetch, import of the core, timeout → fallback
      public-api.js            window.CODKing, .codking-open-form delegation
      recover.js               ?codk_recover=<token> → auto-open
    extras/                    loaded only when enabled → codk-form-extras.js (IIFE)        [WS4]
      index.js                 init(cfg, api)
      sticky.js                sticky mobile bar (BTN-4)
      cart-buttons.js          cart page + cart drawer + quick-buy buttons (BTN-5)
      theme-buttons.js         rename Buy now (BTN-8), preset A interception (BTN-12)
    widget/                    quantity-offer widget on the product page → codk-form-qty-widget.js   [WS4]
      index.js  widget.css
    core/                      Preact → codk-form-core.js (ESM)                              [WS5]
      index.js                 export async function open(ctx), export function preload(features)
      app.jsx                  shell: shadow root, sheet/modal, focus trap, step router
      store.js                 createStore(reducer) + useStore(selector)
      reducer.js  actions.js
      api.js                   post(path, body) (text/plain JSON), retry policy, token refresh
      quote.js                 debounced quote loop with seq
      validate.js              client validation (twin of Engine::FormValidator)
      phone.js                 twin of Engine::Phone
      blocks/  OrderSummary.jsx  Fields.jsx  Field.jsx  Shipping.jsx  Totals.jsx  Submit.jsx  Blocked.jsx
      steps/   FormStep.jsx  Processing.jsx  ThankYou.jsx
      i18n.js                  t(key, vars), loads the locale chunk, merges merchant overrides
      styles/core.css
    chunks/                    lazy ESM chunks, one file each                                [WS5]
      otp.jsx  payment-option.jsx  handoff.js  qty-offer.jsx  bumps.jsx  downsell.jsx  upsell.jsx
      discount.jsx  custom-fields.jsx  content-blocks.jsx  india.jsx  autocomplete.js  threshold.jsx
      embedded.js  pixels-meta.js  pixels-tiktok.js  pixels-google.js  pixels-snap.js  pixels-pinterest.js
    i18n/                      en.json hi.json ar.json fr.json es.json hu.json sr.json ur.json   [WS5]
  test/                        node --test unit tests (validate, phone, money, reducer, selectors) + fixtures/ copied from the backend engine fixtures
  harness/                     G.12                                                           [WS5]
```

Embed: `payment-customization-js/extensions/cod-king-otp-extension/blocks/cod-form-embed.liquid` [WS4]. Built files: `extensions/cod-king-otp-extension/assets/codk-form-*.js` (generated, committed).

### G.2 The embed block (`blocks/cod-form-embed.liquid`)

Schema: `{"name": "COD King – COD Form", "target": "body", "settings": []}` — **no** `"javascript"` / `"stylesheet"` keys (they would load on every page while the block is on, F30). Everything is inside one Liquid condition:

```liquid
{%- liquid
  assign cf = shop.metafields.codk.cod_form.value
  assign codkf_on = false
  if cf and cf.enabled
    assign codkf_on = true
  endif
  if codkf_on and cf.countries.size > 0
    unless cf.countries contains localization.country.iso_code
      assign codkf_on = false
    endunless
  endif
  if codkf_on and cf.test_only
    unless request.design_mode
      assign codkf_test_gate = true
    endunless
  endif
  assign pt = request.page_type
  # page gate: product → cf.pages.product; cart → cf.pages.cart; any other page → cf.pages.drawer or cf.pages.quick_buy
  # product gate (pt == 'product'): pid = product.id | append: ''
  #   cf.vis.exc_p contains pid → off;  cf.vis.scope == 'selected' and not (inc_p contains pid or a product collection in inc_c) → off
  #   cf.rules.hide_p contains pid → off;  cf.rules.show_p.size > 0 and not contains pid → off
  #   any product collection id in cf.vis.exc_c or cf.rules.hide_c → off;  cf.rules.show_c.size > 0 and no collection in it → off
  #   vendor (downcase) contained in an entry of cf.rules.hide_vendors → off; show_vendors non-empty and not listed → off
  #   product.selling_plan_groups.size > 0 and product.requires_selling_plan → off
-%}
{%- if codkf_on -%}
<style>…button + slot + hide-toggle CSS, minified, only the rules needed…</style>
<script>window.__CODKF__={…};</script>
<script>…slot script (≤ 600 B)…</script>
<script src="{{ 'codk-form-loader.js' | asset_url }}" defer id="codkf-loader"></script>
{%- endif -%}
```

`window.__CODKF__` (emitted with `| json` per value; keys are fixed):

```js
{
  v: 37, api: "https://app.codking.tech", shop: "brand.myshopify.com",
  page: "product",                       // product | cart | other
  locale: "hu", country: "HU", currency: "HUF", moneyFormat: "{{amount_no_decimals}} Ft", root: "/",
  capFallback: false, testOnly: false, design: false,
  pages: {product: true, cart: true, drawer: true, quick_buy: false},
  vis: {min: null, max: 5000000, hideOos: true, overflow: false},
  rules: {hideV: [], min: null, max: null},          // only what must be checked per variant / per total in JS
  btn: {preset: "B", label: "Fizetés utánvéttel", subtitle: "", style: {…}, placement: {…},
        sticky: {enabled: true, label: "…{total}"}, cart: {enabled: true, label: "…", selector: ""},
        drawer: {enabled: true, selector: ""}, quickBuy: {enabled: false, selector: ""}},
  theme: {rename: "", hide: {add_to_cart: false, buy_now: false, checkout: false, wallets: false}},
  features: ["otp", "partial"],
  qo: null,                               // the one matching quantity offer (labels already resolved to the locale) or null
  embedded: {enabled: false, selector: "", position: "after"},
  p: {id: "8111", handle: "widget", title: "Widget", vendor: "acme", image: "https://…",
      variant: "44111", variants: [["44111", 1, 199900], ["44112", 0, 199900]]}   // [id, available 0/1, price cents]; max 250, then overflow → server check
}
```

Labels are resolved to one string in Liquid (`request.locale.iso_code` → language part → `default`). `p` is emitted only on product pages. Hide toggles (BTN-9) are pure CSS in the inline `<style>` (no flash, no JS): Add to cart `form[action*="/cart/add"] [name="add"]`, Buy now `.shopify-payment-button`, Checkout `[name="checkout"],#checkout,.cart__checkout`, wallets `shopify-accelerated-checkout,shopify-accelerated-checkout-cart,.additional-checkout-buttons,.shopify-payment-button__more-options` — each `{display:none!important}`.

**Slot script (NFR-2).** Runs synchronously at the end of `<body>` (before first paint in practice): finds the anchor — `btn.placement.selector` when `custom`, else the closest common container of the first match of `form[action*="/cart/add"] [name="add"]` and the `.shopify-payment-button` in the same form — and inserts `<div class="codkf-slot" data-codkf-slot style="min-height:<style.height + 10>px">` above or below it. The deferred loader fills the slot; if the loader decides not to render (variant not eligible), it collapses the slot.

Budget (NFR-1, product decision 14): **default path** = inline CSS + config + slot script (≤ 1.8 KB gz) + `codk-form-loader.js` (≤ 3.2 KB gz) = **≤ 5 KB gz** on a product page with preset B. **Extras** — sticky bar, cart-page / drawer / quick-buy buttons, Buy now rename, preset A — are **not** in the loader: they are in `codk-form-extras.js` (≤ 1.5 KB gz), which the loader imports only when at least one of them is enabled for the current page. Hard ceiling with all extras on: **6.5 KB gz**. Both limits are in `size-limits.json` (`"default_path": 5120`, `"with_extras": 6656`, computed as inline output of `harness/render-embed.mjs` + the files) and the build fails over either. Zero bytes when `codkf_on` is false.

**Coexistence with the Express embed (F30, product decision 3).** The two embeds are separate blocks with separate toggles, and `app-embed.liquid` is not edited. While the old "COD King OTP Block" embed is on **and** (`enable_pre_order_otp` or `partial_payment_enabled`), the theme's Buy now and Checkout buttons open Express instead of Shopify checkout; the COD button is not affected. Handling: **warn, never block.** `GET /cod_form/setup` reports `embed.legacy_enabled` and, only under that condition, the health item `legacy_embed_on` (severity `warning`); the Setup screen shows a warning banner (copy in H.8). Neither the mode switch nor the checklist is blocked. WS4 also delivers `docs/cod-form/snippets/ws4-app-embed.liquid.md` — the guard `{%- unless shop.metafields.codk.cod_form.value.enabled -%} … {%- endunless -%}` around the block body — for the owner's next embed release; it is not applied in this project.

### G.3 Loader behaviour (`codk-form-loader.js`)

1. `cfg = window.__CODKF__`; `base = document.currentScript.src.replace(/[^/]+$/, "")` (the extension asset directory on Shopify's CDN — this is how every chunk URL is resolved; Liquid's `asset_url` gives the loader URL, the loader derives the rest).
2. `testOnly` → continue only when `location.search` contains `codk_preview=`; the token is stored in `sessionStorage.codkf_preview` and sent as `preview_token`.
Steps 4, 5, 6 and the preset A part of step 3 live in `codk-form-extras.js`; the loader injects it (`<script src=base + "codk-form-extras.js">`) only when `btn.sticky.enabled` (product page), `btn.cart.enabled` / `btn.drawer.enabled` / `btn.quickBuy.enabled` for the current page, `theme.rename` non-empty, or `btn.preset === "A"`.
3. Product page: read variant/quantity (G.5), run `visibility.js` (variant in `rules.hideV`, variant unavailable and `vis.hideOos`, price × quantity outside `vis`/`rules` min–max) → render or collapse. Fill the slot with `<button type="button" class="codkf-btn codking-open-form" data-codkf-source="product">` (light DOM, styled by the inline CSS; inherits the theme font). Preset `A`: no button; `theme-buttons.js` adds a capture-phase `click` listener on `document` for unbranded `BUY_NOW` selectors, calls `preventDefault()` + `stopImmediatePropagation()` and opens the form with `source: "product"` and `payOnline: true`.
4. Sticky button (BTN-4): `IntersectionObserver` on the main button; a fixed bottom bar (`.codkf-sticky`) is shown on viewports ≤ 749 px while the main button is out of view.
5. Cart page / drawer / quick-buy: `cart-buttons.js` inserts a COD button before the first match of `CART_CHECKOUT` / `CART_DRAWER` (or the configured selector) and keeps it there with one `MutationObserver` on `document.body` (childList, subtree; callback throttled to one run per animation frame; disconnects on pages with no match after 10 s unless `pages.drawer`).
6. Rename Buy now (BTN-8, preset C): for each match of `BUY_NOW` that is not branded (`.shopify-payment-button__button--branded`, anything inside `shopify-accelerated-checkout`, `[data-shopify-buttoncontainer]`), set the text to `theme.rename` (+ `prepaid_label`) when it differs. A `MutationObserver` on each `.shopify-payment-button` container (childList + characterData, subtree) re-applies it after variant changes and theme re-renders; writes are skipped when the text already matches (no loop). The button's behaviour is untouched.
7. Intent prefetch (NFR-15): on the first `touchstart` / `pointerenter` / `focus` on any COD button: `import(base + "codk-form-core.js")`, then `core.preload({base, features: cfg.features, locale: cfg.locale})`. On tap: `core.open(ctx)`; if the import rejects or does not resolve in 6 s → `goToCheckout`. The contract between loader and core is exactly:
   `ctx = {cfg, base, source, variantId, quantity, properties, tierIndex, items, payOnline, previewToken, recoveryToken, opener}` — `items` is null for product sources (the core builds it from `variantId`/`quantity`/`properties`) and the `/cart.js` items for cart sources; `opener` is the element to return focus to. `open` returns a promise that resolves when the form is visible and rejects when the core decides to fall back (after calling `goToCheckout` itself).
8. `capFallback` → tap calls `goToCheckout` directly.
9. Funnel: one `cf_button_view` per page view per button kind via `sendBeacon` to `/api/form/events` (only when consent allows analytics, G.8).
10. Feature → chunk file names the core preloads from `cfg.features`: `otp` → `codk-form-otp.js`; `partial` → `codk-form-payment-option.js` + `codk-form-handoff.js`; `qty_offer` → `codk-form-qty-offer.js`; `bumps` → `codk-form-bumps.js`; `downsell` → `codk-form-downsell.js`; `upsell` → `codk-form-upsell.js`; `discount` → `codk-form-discount.js`; `custom_fields` → `codk-form-custom-fields.js`; `content` → `codk-form-content-blocks.js`; `india` → `codk-form-india.js`; `autocomplete` → `codk-form-autocomplete.js`; `threshold` → `codk-form-threshold.js`; `embedded` → `codk-form-embedded.js`; `pixels` → `codk-form-pixels-<meta|tiktok|google|snap|pinterest>.js` per the session's pixel list; `preset_a` → loader extras only.
11. Quantity-offer widget: when `cfg.qo` → `import(base + "codk-form-qty-widget.js")`, rendered above the buy buttons; selecting a tier sets the form's quantity input (when present) and is carried into `open()` as `quantity` + `tierIndex` (OFF-3). For the prepaid path (OFF-4) the widget also writes the cart attribute `_codkDiscounts` (`"<variantId>:<discount>|<tier label>"`, F34) via `/cart/update.js` when the buyer adds to cart or uses Buy now. This browser-written attribute is the accepted trust model for the prepaid path in this release (product decision 11); form orders are not exposed because the server recomputes offers.

### G.4 Public API and hooks (BTN-10)

```js
window.CODKing = {
  version: "1.0.0",
  openForm({variantId, quantity = 1, properties = {}, source = "api"} = {}),   // no variantId → current product page selection, or the cart
  close(),
  on(eventName, handler), off(eventName, handler),
  registerPayOnlineHandler(fn)       // PRE-6: fn(payload) → true to take over the Pay online step (RabbitPay hook, interface only)
};
```

- Any element with class `codking-open-form` opens the form on click (delegated listener on `document`). Optional attributes: `data-variant-id`, `data-quantity`.
- DOM events on `document` (`CustomEvent`, `detail` object, `bubbles: true`): `codking:ready`, `codking:button:render`, `codking:form:open`, `codking:form:step` (`detail.step`), `codking:form:close`, `codking:form:submit`, `codking:form:error` (`detail.code`), `codking:order:created` (`detail.order`), `codking:handoff` (`detail.kind`), `codking:pay_online` (cancelable — PRE-6), `codking:fallback` (`detail.reason`).
- `codking:pay_online` detail / `registerPayOnlineHandler` payload: `{session_id, shop, currency, total_cents, items: [{variant_id, quantity, price_cents}], contact, address, discounts, return_url}`. If the event is `preventDefault()`-ed or a handler returns `true`, the form does not redirect to checkout.

### G.5 Reading the product page and the cart (BTN-11)

At tap time (always authoritative) and on change (to update `{total}` and eligibility):
- **Variant**: `form[action*="/cart/add"] [name="id"]` of the product form nearest to the slot → else `new URLSearchParams(location.search).get("variant")` → else `window.ShopifyAnalytics?.meta?.selectedVariantId` → else `cfg.p.variant`.
- **Quantity**: `[name="quantity"]` in that form (or one referencing it by the `form` attribute) → integer ≥ 1, default 1; a selected quantity-offer tier overrides it.
- **Properties**: every `[name^="properties["]` field of the form → `{name: value}` (checked radios/checkboxes only).
- **Selling plan**: a non-empty `[name="selling_plan"]` → the button uses `goToCheckout` (subscriptions are not COD-form orders).
- **Change detection**: delegated `change` and `input` listeners on the product form, a `MutationObserver` on the `value` attribute of `[name="id"]`, and a wrapper around `history.replaceState` (themes update `?variant=`). Each trigger re-reads after one animation frame.
- **Cart**: `fetch(cfg.root + "cart.js", {credentials: "same-origin"})` → `items.map(i => ({variant_id: String(i.variant_id), quantity: i.quantity, properties: i.properties || {}}))`, plus `token` (cart token, for the hand-off) and `attributes`. An empty cart → the cart button does nothing. After a COD order from `cart` / `drawer`: `POST cart/clear.js`. A product-page order never touches the cart.

### G.6 Core form: state, steps, accessibility, CSS

**Store** (`store.js`, ~40 lines, no signals library in the core): `createStore(reducer, initial)` → `{getState, dispatch, subscribe}`; `useStore(selector)` with `useSyncExternalStore`-style subscription.

```js
state = {
  ctx: {source, shop, api, locale, country, currency, moneyFormat, rtl, test},
  session: {token, id, expiresAt, configVersion, cap},
  config: {form, countrySchema, countries, otp, offers, features, pixels, security, handoff},
  texts: {},                                   // defaults (locale chunk) merged with overrides
  cart: {items: [{variant_id, quantity, properties}], cartToken},
  values: {first_name, last_name, phone, email, country, address1, address2, province, city, zip, note, gst_number, marketing_consent, custom: {}},
  touched: {}, errors: {},                     // field key → text key
  selection: {shippingRateId, bumps: [{offer_id, quantity}], discountCode, downsellOfferId, tierIndex, paymentOptionId},
  quote: {status: "idle"|"loading"|"ready"|"error", seq: 0, data: null},
  otp: {status: "idle"|"sending"|"sent"|"verifying"|"verified"|"error", channel, attemptsLeft, resendAt, verifiedPhone},
  step: "form",                                // form | otp | payment | processing | upsell | thankyou | blocked
  submit: {attempt: 1, status: "idle"|"submitting"|"error", error: null, startedAt},
  order: null, upsell: null,
  ui: {closes: 0, downsellShown: false, firstInputSent: false, openedAt}
}
```

Step flow (spec §4): `form` → (client validation, final quote) → `otp` if `quote.otp_required` and `otp.verifiedPhone !== values.phone` → `payment` if `quote.payment_options` → `processing` → `upsell` if returned → `thankyou`. "Back" from `otp` returns to `form` with all values kept (OTP-4). Closing shows the downsell (if any and `ui.closes + 1 >= trigger_after_closes`, once per session), else an exit confirmation only when a field was touched. Values are mirrored to `sessionStorage.codkf_draft_<shop>` (no OTP codes) so a reload or re-open restores them.

**Rendering**: one host element `<div id="codkf-root">` appended to `<body>` with an open **shadow root**; all form CSS is inside it (no leakage in either direction). `:host{all:initial;font-family:inherit;}` so the font inherits from the theme (FRM-8). Class prefix `codkf-` everywhere (also for the light-DOM button/sticky/slot CSS). Design tokens become CSS custom properties on the host: `--codkf-primary`, `--codkf-on-primary`, `--codkf-text`, `--codkf-muted`, `--codkf-bg`, `--codkf-surface`, `--codkf-border`, `--codkf-error`, `--codkf-radius`, `--codkf-field-radius`. Layout uses logical properties only (`margin-inline`, `padding-inline`, `inset-inline`, `text-align: start`) and `dir="rtl"` on the dialog when `ctx.rtl` (FRM-9). Bottom sheet below 750 px, centred modal (max-width 480 px) above (FRM-1). Body scroll lock by `overflow:hidden` on `<html>` (restored on close).

**Accessibility (NFR-10)**: `role="dialog"`, `aria-modal="true"`, labelled by the title; focus moved to the first field on open and restored to the opener on close; focus trap on Tab/Shift+Tab; Escape closes; every input has a visible `<label for>`; errors use `aria-invalid` + `aria-describedby`; totals region `aria-live="polite"`; minimum 44 px touch targets; contrast of merchant colours is checked in the designer (warning under 4.5:1).

**Quote loop**: any change of items, quantity, country, province, zip, shipping rate, bumps, discount code → `quote.js` debounces 250 ms, increments `seq`, posts D.2, ignores stale responses. Phone/email blur → D.3.

**Embedded mode (FRM-20)**: `chunks/embedded.js` mounts the same app inside the element given by `cfg.embedded.selector` (shadow root, no overlay); the session is opened on first interaction or when the element enters the viewport.

### G.7 Texts and i18n (FRM-10, FRM-19)

- Canonical defaults: `src/i18n/<locale>.json` for `en, hi, ar, fr, es, hu, sr, ur` (flat `{key: string}`), each built into `codk-form-i18n-<locale>.js` (default export = the object). `en` is also compiled into the core as the last fallback.
- Locale resolution: `cfg.locale` → its language part → `en`. The chunk is fetched in parallel with the session call.
- Merge order: default locale chunk < `form.config.texts.en` < `form.config.texts[locale]` (overrides returned by the session).
- `scripts/export-texts.mjs` writes `cod-confirm/config/cod_form/default_texts.json` (`{"en": {…}, "hi": {…}, …}`), which the admin API serves (`GET /cod_form/forms/defaults`) and the backend uses for server-rendered descriptions. It is a generated file, committed, owner WS5.
- Fixed English defaults (product): `title` "Cash on Delivery"; `submit` "Complete order — {total}"; `pay_online` "Pay online instead"; `error_blocked` "Cash on delivery is not available for this order."; `error_no_shipping` "We don't deliver to this address yet."; `thank_you_message` "Thank you {first_name}! Your order {order_name} is confirmed."; `powered_by` "Powered by COD King".
- Variables use single braces: `{total}`, `{count}`, `{seconds}`, `{phone}`, `{remaining}`, `{order_name}`, `{first_name}`.

Text keys (complete list; error keys are also the `message_key` values of the API):

```
title close loading powered_by secure_note
summary_title quantity item_singular item_plural you_save out_of_stock
contact_title address_title
label_first_name label_last_name label_phone label_email label_country label_address1 label_address2
label_province label_city label_zip label_pincode label_gst_number label_note label_marketing_consent
placeholder_first_name placeholder_last_name placeholder_phone placeholder_email placeholder_address1
placeholder_address2 placeholder_province placeholder_city placeholder_zip placeholder_gst_number placeholder_note
error_required error_first_name error_last_name error_phone error_phone_too_short error_phone_too_long
error_phone_prefix error_email error_address1 error_province error_city error_zip error_gst_number
error_latin_only error_pattern error_generic error_network error_out_of_stock error_total_changed
error_blocked error_limit_reached error_max_quantity error_not_eligible error_no_shipping
error_otp_send error_otp_invalid error_otp_attempts error_order_failed
error_discount_invalid error_discount_not_combinable error_discount_minimum
shipping_title shipping_free shipping_enter_address
discount_title discount_placeholder discount_apply discount_remove discount_applied
subtotal discount shipping cod_fee tax tax_included total savings
submit submit_processing pay_online pay_online_hint
otp_title otp_subtitle otp_placeholder otp_verify otp_verifying otp_resend otp_resend_in otp_change_number
otp_via_sms otp_via_whatsapp
payment_title payment_full_cod payment_partial payment_prepaid payment_pay_now payment_pay_later payment_continue
bump_add upsell_timer
processing_title processing_subtitle
thank_you_title thank_you_message thank_you_order thank_you_continue thank_you_whatsapp
exit_title exit_stay exit_leave
```

Custom fields and content blocks add `label_cf_<id>`, `placeholder_cf_<id>`, `error_cf_<id>` and `block_<id>_text` keys in the merchant's `texts`.

### G.8 Consent and pixels in the browser (TRK-1, TRK-6)

`shared/consent.js`: `window.Shopify?.customerPrivacy` → `{analytics: analyticsProcessingAllowed(), marketing: marketingAllowed(), sale_of_data: saleOfDataAllowed()}`; when the API is absent all three are `true`. Sent with the session call; `general.consent.respect_customer_privacy` (default true) makes the server and the pixel chunks skip marketing pixels without `marketing` consent and funnel analytics without `analytics` consent. Pixel chunks (`pixels-*.js`) load the vendor snippet only if its global (`fbq`, `ttq`, `gtag`, `snaptr`, `pintrk`) is missing, call `init` for each configured pixel id, and fire the events of I.2 with the shared event ids. They are loaded after the form is interactive (`requestIdleCallback`), never before.

### G.9 Hand-off to Shopify checkout — `chunks/handoff.js`

Used for (a) the partial option, (b) a 100 % prepaid rule, (c) Pay online for blocked buyers and preset A (PRE-1), (d) nothing else. It replicates today's flow (F33) step by step:

1. `POST /api/form/handoff` (D.8) → `cart_attributes`, `discount_code`, `buyer_identity`, `storefront_token`.
2. **Cart contents.** Source `product` / `api` / `embedded`: `POST cart/clear.js`, then `POST cart/add.js` with `{items: [{id, quantity, properties}]}` (retry up to 3 times, as `shopifyAddToCartForBuyNow` does); a 422 → show `error_out_of_stock` and stay in the form. Source `cart` / `drawer`: the cart is already right.
3. **Partial only:** make sure the dummy variant id is known — it comes in the hand-off response (`_partial_product_variant`); when the server has none yet it calls the same logic as `GET /order_confirmations/partial_dummy_variant_id` before answering.
4. **Attributes.** `POST cart/update.js` with `{attributes: cart_attributes, note: ""}` and, when `discount_code` is present, `{discount: discount_code}` in the same body. Attribute meaning (unchanged from today): `_codkAmountType`, `_codkAmountValue` (rule), `_codkCheckoutMode` (`"cod_only"` or `""`), `_codkFinalDiscountValue`, `_codkPaymentDescription`, `_codkDiscounts`, `_codkImageURLs`, `_codkOriginalTotal`, `_partial_product_variant`, `partial_payment_variants` (JSON array of numeric variant ids; `null` for a 100 % rule), `_partialPaymentProduct` (`true` for partial and 100 % rules), `_codkBundleMode` (`"expand"` when `Setting#partial_expand_flow_enabled`), `_codkSessionId`, `_otpVerifiedPhoneNumber`, `_codkCountryCode`, plus the new `_codkFormSessionId`, `_codkFormId`.
5. **Buyer identity.** `GET cart.js` → `token`; Storefront API (`https://<shop>/api/2025-07/graphql.json`, header `X-Shopify-Storefront-Access-Token: storefront_token`) mutation `cartBuyerIdentityUpdate(cartId: "gid://shopify/Cart/<token>", buyerIdentity: buyer_identity)` — the same mutation and input shape as `performBuyerIdentityUpdate` (`cartService.js:271-394`). When the buyer gave no email, `email` is omitted (no placeholder). A failure here is not fatal: continue to step 6 (the buyer re-types the address at checkout); log `cf_client_error`.
6. `localStorage["codk-updated-cart"] = "true"` (kept for parity with the existing revert logic), emit `codking:handoff`, then `location.assign(cfg.root + "checkout")`.

The existing cart transform, discount and payment functions then do exactly what they do today; the order is created by Shopify checkout, and the webhook hook (F.5) tags it and counts it.

For Pay online when the Storefront token is missing: fall back to a cart permalink for product sources — `/cart/<variant>:<qty>?checkout[email]=…&checkout[shipping_address][first_name]=…&…` — and to plain `/checkout` for cart sources.

### G.10 Size budget (gzip; enforced by `build.mjs`, NFR-18)

| Output | Budget | Content |
| --- | --- | --- |
| inline (Liquid) | 1.8 KB | CSS + config + slot script |
| `codk-form-loader.js` | 3.2 KB | G.3 default path (inline + loader ≤ 5 KB) |
| `codk-form-extras.js` | 1.5 KB | sticky bar, cart / drawer / quick-buy buttons, Buy now rename, preset A (inline + loader + extras ≤ 6.5 KB) |
| `codk-form-core.js` + shared chunk | **32 KB** (limit 35, NFR-15) | Preact + hooks (~4.6), app shell + store (~4), blocks and fields (~9), validation + phone (~3), api/quote (~2), CSS as string (~5), en texts (~2), thank-you/processing (~1.5) |
| `codk-form-i18n-<locale>.js` | 2.5 KB each | |
| `codk-form-otp.js` | 2 KB | |
| `codk-form-payment-option.js` + `codk-form-handoff.js` | 1.5 + 2 KB | |
| `codk-form-qty-offer.js`, `-bumps.js`, `-downsell.js`, `-upsell.js`, `-threshold.js`, `-discount.js` | ≤ 2 KB each | |
| `codk-form-custom-fields.js`, `-content-blocks.js`, `-india.js`, `-embedded.js` | ≤ 2.5 KB each | |
| `codk-form-autocomplete.js` | 1.5 KB | loads Google Places with the merchant's key (INT-3) |
| `codk-form-pixels-*.js` | ≤ 1.2 KB each | |
| `codk-form-qty-widget.js` | 3 KB | product-page widget, plain JS |

No dependency other than `preact` (NFR-17). Province and city lists are never bundled (D.11).

### G.11 Build (`build.mjs`)

```js
import { build } from "esbuild";
const outdir = "../../extensions/cod-king-otp-extension/assets";
// 0) delete outdir/codk-form-* (stale hashed chunks)
// 1) loader + widget: classic scripts
await build({ entryPoints: {"codk-form-loader": "src/loader/index.js", "codk-form-extras": "src/extras/index.js", "codk-form-qty-widget": "src/widget/index.js"},
  bundle: true, format: "iife", minify: true, target: ["es2019", "safari13"], outdir, legalComments: "none",
  loader: {".css": "text"}, define: {__CODKF_VERSION__: JSON.stringify(pkg.version)} });
// 2) core + lazy chunks + i18n: ES modules with shared-code splitting
await build({ entryPoints: {"codk-form-core": "src/core/index.js", "codk-form-otp": "src/chunks/otp.jsx", /* … one per chunk … */
    "codk-form-i18n-en": "src/i18n/en.json" /* … */},
  bundle: true, format: "esm", splitting: true, minify: true, target: ["es2019", "safari13"], outdir,
  entryNames: "[name]", chunkNames: "codk-form-c-[hash]", jsx: "automatic", jsxImportSource: "preact",
  loader: {".css": "text", ".json": "json"}, legalComments: "none", sourcemap: "external", /* maps moved to ./maps, not shipped */ });
// 3) gzip every output, compare with size-limits.json, exit 1 when over budget; print a table
```

- Entry files have stable names (the loader and the core import them as `base + "codk-form-<name>.js"`); shared chunks are hashed and imported relatively, which works because the extension version is part of the CDN path.
- `npm run build`, `npm run dev` (watch + harness), `npm test` (`node --test test/`), `npm run size`, `npm run export:texts`, `npm run e2e`.
- Risk to verify on a development store before P1 sign-off: cross-origin `import()` from `cdn.shopify.com/extensions/…` needs CORS headers on the asset responses. If they are missing, switch step 2 to `format: "iife"` with a tiny chunk registry (`window.__codkf.c[name]`) and `<script>` injection; the module boundaries stay the same.
- Storefront errors (NFR-13): no Sentry SDK in the bundle. `core/api.js#reportError(err, where)` posts a `cf_client_error` event (message, stack ≤ 2 KB, version, chunk) to `/api/form/events`; the server forwards it with `Sentry.capture_message` (tag `cod_form_storefront`).

### G.12 Local harness (no Shopify needed) — `harness/`

```
harness/
  mock-server.mjs          node:http, no dependencies, port 4321
  pages/product.html  cart.html  home.html  pagebuilder.html     static "theme" pages with a real product form, Buy now, cart drawer markup
  fixtures/metafield.json  session.json  quote.json  order.json  geo-HU.json  geo-IN.json  scenarios.json
  render-embed.mjs         JS port of the embed's Liquid decisions: metafield.json + page → the same inline <style>/<script> output
  e2e/*.spec.mjs           Playwright: open form, quote update, OTP path, partial hand-off, blocked buyer, cap fallback, bundle failure fallback, RTL, a11y (focus trap)
```

`mock-server.mjs` serves: the pages (with the embed output injected by `render-embed.mjs`), `/assets/*` from the extension `assets/` directory, the Shopify Ajax API (`/cart.js`, `/cart/add.js`, `/cart/update.js`, `/cart/clear.js`, in-memory cart), `/checkout` (a page that prints the cart, its attributes and the buyer identity it received — used to assert hand-offs), `/api/2025-07/graphql.json` (accepts `cartBuyerIdentityUpdate`), and `/api/form/*` implementing the contracts of section D from the fixtures. Scenario selection: `?scenario=default|otp|partial|blocked|cap|kill|slow_order|order_fail|session_fail|no_rate|rtl`. It can also proxy `/api/form/*` to a real Rails server with `API_PROXY=http://localhost:3000` (the Rails side then needs `COD_FORM_ALLOW_LOCALHOST=true`).

---

## H. Admin UI (React 18 + Polaris 12, `app/javascript/packs/`)

### H.1 Registry (`Pages/SettingsHub/registry.js`) — DSH-1..4

Add as the **first** element of `SETTINGS_GROUPS`:

```js
{ id: "cod-form", labelKey: "settings_hub.group_cod_form", label: "COD Form" },
```

Add at the top of `SETTINGS_ITEMS` (order matters: `Setup` must stay before the others because `findItemByPath` uses longest-prefix matching, and `/features/cod-form` is a prefix of every other path — the longer candidates win for sub-pages, DSH-2):

```js
const codFormVisible = (ctx) => ctx.codForm?.moduleEnabled === true;

{ id: "cod-form-setup",    group: "cod-form", labelKey: "settings_hub.item_cod_form_setup",    label: "Setup",            icon: SettingsIcon,        path: "/features/cod-form",          keywords: ["cod form", "order form", "enable", "app embed", "countries", "test order", "cap", "usage"], isVisible: codFormVisible },
{ id: "cod-form-buttons",  group: "cod-form", labelKey: "settings_hub.item_cod_form_buttons",  label: "Buttons",          icon: ButtonIcon,          path: "/features/cod-form/buttons",  keywords: ["buy button", "buy now", "cod button", "sticky", "rename", "hide add to cart", "preset"], isVisible: codFormVisible },
{ id: "cod-form-designer", group: "cod-form", labelKey: "settings_hub.item_cod_form_designer", label: "Form designer",    icon: PaintBrushFlatIcon,  path: "/features/cod-form/designer", keywords: ["fields", "design", "texts", "translation", "thank you", "publish", "template", "custom field"], isVisible: codFormVisible },
{ id: "cod-form-shipping", group: "cod-form", labelKey: "settings_hub.item_cod_form_shipping", label: "Shipping rates",   icon: DeliveryIcon,        path: "/features/cod-form/shipping", keywords: ["shipping", "delivery", "rates", "free shipping", "province"], isVisible: codFormVisible },
{ id: "cod-form-fraud",    group: "cod-form", labelKey: "settings_hub.item_cod_form_fraud",    label: "Fraud protection", icon: ShieldCheckMarkIcon, path: "/features/cod-form/fraud",    keywords: ["block", "blacklist", "fake orders", "limit", "ip", "phone", "rto", "blocked attempts"], isVisible: codFormVisible },
{ id: "cod-form-offers",   group: "cod-form", labelKey: "settings_hub.item_cod_form_offers",   label: "Offers",           icon: DiscountIcon,        path: "/features/cod-form/offers",   keywords: ["upsell", "downsell", "order bump", "quantity offer", "bundle", "a/b test", "free gift"], isVisible: codFormVisible },
```

- New icons `SettingsIcon`, `ButtonIcon`, `DeliveryIcon`, `ShieldCheckMarkIcon` are added to `Pages/SettingsHub/icons.jsx` (vendored Polaris v9 SVG paths, same pattern as the file).
- `SettingsHub.jsx:480-483`: `visibilityCtx` gains `codForm: useCodFormBootstrap()` (H.3). Until the bootstrap call resolves the group is hidden; it never flashes for shops without the module.
- `/features` is already in `WRAPPED_PREFIXES`; no change there. Nothing is added to `ui-nav-menu` in `app/views/layouts/embedded_app.html.erb`.

### H.2 Routing (`Pages/Home.jsx`)

In `renderRouteContent()` (line 251), **before** the `/features/otp…` branch:

```js
} else if (normalizedLocation === "/features/cod-form" || normalizedLocation.startsWith("/features/cod-form/")) {
  return <CodFormApp path={normalizedLocation} />;
} else if (normalizedLocation === "/integrations/tiktok" || normalizedLocation === "/integrations/form-pixels") {
  return <FormPixelsPage path={normalizedLocation} />;
} else if (normalizedLocation === "/integrations/google-sheets") {
  return <GoogleSheetsPage />;
```

and `/usage-analytics/cod-form` is added to the existing `/usage-analytics…` condition (lines 330-335). `CodFormApp`, `FormPixelsPage`, `GoogleSheetsPage` are `React.lazy` imports (the admin bundle must not grow for shops that never open them).

### H.3 Data layer

- `Pages/CodForm/api.js` — an `axios.create()` instance with the same request interceptor as `Services/Api.js:6-24` (`Authorization: Bearer ${await shopify.idToken()}`, `X-CSRF-Token`) and **no** `humps` interceptors. Exports `get(path, params)`, `post`, `put`, `del`, `upload(path, formData)`; all paths are relative to `/cod_form`.
- `Pages/CodForm/useCodFormBootstrap.js` — module-level cache + subscription; first call fetches `GET /cod_form/bootstrap`; returns `{moduleEnabled, mode, tier, gates, usage, currency, moneyFormat, shopCountry, locales, preview}` (camelCased by hand in this one file) or `null` while loading. `refreshBootstrap()` re-fetches (after a mode switch).
- `Pages/CodForm/useResource.js` — the standard screen pattern: `const {data, setData, original, isDirty, loading, saving, error, save, discard, reload} = useResource({load: () => api.get("/setup"), save: (d) => api.put("/setup", d)})`. `isDirty` is a deep comparison with `original`.
- Save bar: the declarative App Bridge v4 `<SaveBar open={isDirty}>` with `Save` / `Discard` buttons, exactly as `Components/CODFeesSettings.jsx:186-198`; toast `shopify.toast.show(I18n.t("admin.settings_saved"))`. Wrapped once in `Pages/CodForm/components/ScreenSaveBar.jsx`.
- Resource pickers: `shopify.resourcePicker({type: "product" | "collection" | "variant", multiple: true, selectionIds})` (App Bridge v4) in `components/ResourceTargetPicker.jsx`; ids are stored as numeric strings.
- Gates: `components/Gate.jsx` — `<Gate feature="order_bumps">…</Gate>` renders children when `gates[feature].allowed`, else an upgrade card linking to `/subscription` with the required tier. A 402 from the API shows the same card.
- Navigation inside the module: `navigateTo(path)` from `app/javascript/utils/navigate` (existing helper), so the hub URL rewrite keeps working.

### H.4 Files — `app/javascript/packs/Pages/CodForm/`

```
CodFormApp.jsx                     path → screen switch (below); renders <ModuleDisabled/> when bootstrap.moduleEnabled is false
api.js  useCodFormBootstrap.js  useResource.js  money.js  constants.js (countries list, locales, feature keys)
components/
  ScreenSaveBar.jsx  Gate.jsx  ResourceTargetPicker.jsx  ColorField.jsx  LocalizedTextField.jsx
  CountryMultiSelect.jsx  MoneyField.jsx  UsageMeter.jsx  ExpressOnlyBanner.jsx  PreviewFrame.jsx  EmptyState.jsx
Setup/
  SetupPage.jsx            ModeCard.jsx (on/off with confirmation modal, DSH-5)  EmbedStatusCard.jsx  ChecklistCard.jsx (DSH-6)
  HealthCard.jsx (DSH-11)  CountriesCard.jsx  VisibilityCard.jsx (pages, products, collections)  OrderTotalCard.jsx
  TestOrderCard.jsx        UsageCard.jsx       AdvancedCard.jsx (COD only through the form, abandonment, upsell window, embedded mode)
Buttons/
  ButtonsPage.jsx          PresetPicker.jsx  ButtonStyleCard.jsx  PlacementCard.jsx  StickyCard.jsx
  CartButtonsCard.jsx      ThemeButtonsCard.jsx (rename + hide toggles)  QuantityWidgetCard.jsx  ButtonPreview.jsx
Designer/
  DesignerPage.jsx         FormsListPage.jsx (FRM-22)  FormTargetingCard.jsx  TemplatesModal.jsx (FRM-21)
  tabs/FieldsTab.jsx  tabs/BlocksTab.jsx  tabs/DesignTab.jsx  tabs/TextsTab.jsx  tabs/ThankYouTab.jsx
  FieldEditor.jsx  CustomFieldModal.jsx  ContentBlockModal.jsx  SortableList.jsx (native HTML5 drag and drop, no new dependency)
  PublishBar.jsx (draft / publish / discard, FRM-11)  DevicePreview.jsx (desktop + mobile frames around PreviewFrame)
Shipping/
  ShippingPage.jsx  RateModal.jsx  ConditionsEditor.jsx  CsvImportModal.jsx      (list paged at 200 rates)
Fraud/
  FraudPage.jsx  BlockListCard.jsx  BlockEntryModal.jsx  LimitsCard.jsx  MaxQuantityCard.jsx
  OtpModeCard.jsx  RtoGatingCard.jsx  BlockedAttemptsTable.jsx
Offers/
  OffersPage.jsx (directory of cards)  OffersListPage.jsx
  QuantityOfferEditor.jsx  BumpEditor.jsx  UpsellEditor.jsx  DownsellEditor.jsx  ThresholdEditor.jsx
  AbTestsPage.jsx  AbTestEditor.jsx  OfferTargetingCard.jsx
Analytics/
  CodFormAnalytics.jsx  FunnelChart.jsx  BreakdownTable.jsx  Filters.jsx
Integrations/
  FormPixelsPage.jsx  PixelModal.jsx  GoogleSheetsPage.jsx  KlaviyoOmnisendCard.jsx
Summary/
  CodFormSummaryCard.jsx   opt-in card (shops not using the form) or usage meter (shops using it) — DSH-9
```

Screen switch in `CodFormApp.jsx`:

| Path | Screen |
| --- | --- |
| `/features/cod-form` | `SetupPage` |
| `/features/cod-form/buttons` | `ButtonsPage` |
| `/features/cod-form/designer` | `FormsListPage` when the shop has more than one form, else `DesignerPage` for the default form |
| `/features/cod-form/designer/:id` | `DesignerPage` |
| `/features/cod-form/shipping` | `ShippingPage` |
| `/features/cod-form/fraud` | `FraudPage` |
| `/features/cod-form/offers` | `OffersPage` |
| `/features/cod-form/offers/:type` (`quantity`, `bumps`, `upsells`, `downsells`, `thresholds`) | `OffersListPage` |
| `/features/cod-form/offers/:type/new`, `/features/cod-form/offers/:type/:id` | the matching editor |
| `/features/cod-form/offers/ab-tests`, `…/ab-tests/:id` | `AbTestsPage`, `AbTestEditor` |

Existing files edited by WS7 only: `Pages/SettingsHub/registry.js`, `Pages/SettingsHub/icons.jsx`, `Pages/SettingsHub/SettingsHub.jsx` (one line), `Pages/Home.jsx`, `Components/AnalyticsDashboardTabs.jsx` (new tab `{ path: "/usage-analytics/cod-form", content: I18n.t("analytics_tabs.cod_form", { defaultValue: "COD Form" }) }` + lazy `CodFormAnalytics`), `Components/Summary.jsx` (render `<CodFormSummaryCard />` next to `OneClickCheckoutCard`, line 845), `Components/Integrations/IntegrationsHub.jsx` (cards: TikTok, Form pixels, Google Sheets, Klaviyo, Omnisend), `Components/PartialPayment/PartialPayment.jsx` (relabel the Express toggle `cod_form_enabled` to "Express order form" — spec §12), `Components/Billing.jsx` (usage + overage rows), the OTP, UI-customization screens (`ExpressOnlyBanner` when `mode === "cod_form"`, DSH-7) `Components/CODShowHide.jsx` (postal help text and warnings, Free-plan note — H.8), `Components/CODFeesSettings.jsx` and `Components/CODFeesSettingsNew.jsx` (Free-plan note — H.8), `Components/QuickOnboardingV2.jsx` (COD Form setup step, DSH-8), `config/localeJson/en.json`.

### H.5 i18n (DSH-13)

Admin strings go into **`config/localeJson/en.json`** (F25), the Crowdin source; the other 17 locale files are produced by Crowdin and are not edited by hand. New top-level section `cod_form` plus additions to existing sections:

```
settings_hub.group_cod_form, settings_hub.item_cod_form_setup, .item_cod_form_buttons, .item_cod_form_designer,
  .item_cod_form_shipping, .item_cod_form_fraud, .item_cod_form_offers
analytics_tabs.cod_form
integrations.tiktok.*, integrations.form_pixels.*, integrations.google_sheets.*, integrations.klaviyo.*, integrations.omnisend.*
partial.express_order_form_toggle
cod_form.common.{save,discard,publish,discard_draft,enabled,disabled,upgrade_required,upgrade_cta,learn_more,add,edit,delete,cancel,all_products,selected_products,collections,countries,preview,desktop,mobile}
cod_form.setup.{title,subtitle,mode_card_title,mode_on,mode_off,mode_confirm_title,mode_confirm_body,mode_confirm_cta,embed_title,embed_on,embed_off,embed_open_editor,legacy_embed_title,legacy_embed_body,legacy_embed_cta,checklist_title,check_embed,check_preset,check_shipping,check_test_order,health_title,health_embed_off,health_legacy_embed_on,health_no_shipping_rate,health_no_country,health_cap_reached,health_cap_flagged,health_otp_unavailable,health_rule_cod_fee_ignored,health_zip_allow_list_no_exact,countries_title,countries_help,visibility_title,pages_product,pages_cart,pages_drawer,pages_quick_buy,order_total_title,order_total_min,order_total_max,order_total_message,hide_oos,test_order_title,test_order_cta,usage_title,usage_of_cap,usage_unlimited,cod_only_through_form,abandonment_title,upsell_window,embedded_title}
cod_form.buttons.{title,preset_title,preset_a,preset_b,preset_c,preset_a_help,preset_b_help,preset_c_help,label,subtitle,total_variable_help,style_title,bg,color,border,radius,shadow,icon,animation,animation_none,animation_pulse,animation_shake,placement_title,placement_below,placement_above,placement_custom,selector,sticky_title,cart_title,drawer_title,quick_buy_title,rename_title,rename_help,hide_title,hide_add_to_cart,hide_buy_now,hide_checkout,hide_wallets,widget_title}
cod_form.designer.{title,forms_title,new_form,default_badge,make_default,duplicate,targeting_title,tab_fields,tab_blocks,tab_design,tab_texts,tab_thank_you,field_required,field_optional,field_hidden,add_custom_field,custom_type_text,custom_type_textarea,custom_type_select,custom_type_radio,custom_type_checkbox,custom_type_date,regex,latin_only,add_block,block_rich_text,block_image,block_trust_badges,block_countdown,block_threshold_bar,design_primary,design_text,design_background,design_radius,design_logo,design_header_title,templates,texts_locale,texts_reset,thank_you_type,thank_you_order_status,thank_you_custom_url,thank_you_message,thank_you_whatsapp,variables_help,unpublished_changes,published_at,contrast_warning,phone_first}
cod_form.shipping.{title,empty_title,empty_body,add_rate,name,description,price,free,conditions,cond_country,cond_provinces,cond_total,cond_weight,cond_quantity,cond_products,import_csv,no_rate_message}
cod_form.fraud.{title,block_title,block_phone,block_email,block_ip,block_add,block_bulk,blocked_message,limits_title,limit_phone,limit_email,limit_ip,limit_orders,limit_hours,limit_message,max_quantity,otp_mode_title,otp_before_order,otp_order_first,otp_risk_based,otp_managed_note,rto_title,rto_band,rto_message,attempts_title,attempts_empty,reason_*}
cod_form.offers.{title,quantity_title,quantity_desc,bumps_title,bumps_desc,upsells_title,upsells_desc,downsells_title,downsells_desc,thresholds_title,thresholds_desc,ab_tests_title,tier_quantity,tier_discount_type,tier_value,tier_label,tier_badge,tier_preselected,overlap_error,bump_kind_variant,bump_kind_custom,checked_by_default,quantity_picker,requires_shipping,taxable,position,trigger_after_closes,timer,window,stacking_title,codes_combine,ab_weight,ab_start,ab_stop,ab_locked}
cod_form.analytics.{title,funnel,button_views,form_opens,first_inputs,shipping_selected,submit_attempts,orders,conversion_rate,revenue,aov,prepaid_redirects,partial_handoffs,filter_country,filter_product,filter_device,compare,export_csv,by_campaign,by_offer}
cod_form.summary.{optin_title,optin_body,optin_cta,usage_title,notice_80,notice_100,flagged_body,flagged_cta}
cod_form.limit_cod.{postal_help,allow_list_warning,allow_list_critical,free_plan_note}
cod_form.cod_fees.{free_plan_note}
cod_form.billing.{usage_line,overage_line}
cod_form.express_only_banner.{title,body,cta}
```

Server-side strings (cap notice emails) go into `config/locales/en.yml` under `cod_form_mailer.*` (owner WS8).

### H.6 Live preview (FRM-11, BTN-7)

`components/PreviewFrame.jsx` renders `<iframe src="/cod_form/preview_frame" sandbox="allow-scripts">` and posts `{type: "codkf:preview", form: draftConfig, button: buttonConfig, texts, locale, device, view: "form" | "button" | "otp" | "thankyou"}` on every change (debounced 150 ms). `CodFormAdmin::PreviewFramesController#show` (`< ActionController::Base`, no auth, no data, `layout false`, response header `Content-Security-Policy: default-src 'none'; script-src https://cdn.shopify.com 'unsafe-inline'; style-src 'unsafe-inline'; img-src https: data:; frame-ancestors https://admin.shopify.com https://*.myshopify.com 'self'`) renders a bare page that imports `<asset_base>codk-form-core.js` and calls `core.preview(payload)` (an export of the core that mounts the form with fixture cart data and no network). `asset_base` comes from the query string and is accepted only when it starts with `https://cdn.shopify.com/extensions/#{ENV['COD_FORM_EXTENSION_UUID']}/`; the admin passes `bootstrap.preview.asset_base` (`cod_form_shop_configs.asset_base`, else `ENV['COD_FORM_ASSET_BASE']`). When neither is known the designer shows a static placeholder with "Open storefront preview" (`preview_url`).

### H.7 Built for Shopify notes (DSH-12, DSH-15)

Polaris components only; every screen inside the hub layout (mobile drawer inherited); no nav-menu change; contextual save bar on every editable screen; all navigation through history `pushState` (hub rewrite); empty states for lists; no forced redirects out of the admin (theme editor and storefront preview open in a new tab with `target="_blank"`).

### H.8 Fixed copy from the product decisions (English source strings for `en.json`)

| Key | Where | Text |
| --- | --- | --- |
| `cod_form.setup.legacy_embed_title` / `_body` / `_cta` | Setup banner (tone warning) + health `legacy_embed_on` | "The older COD King embed is still on" / "While "COD King OTP Block" is on, your theme's Buy now and Checkout buttons open Express checkout instead of Shopify checkout. Your Buy with COD button is not affected. If you no longer use Express checkout, turn that embed off in the theme editor." / "Open theme editor" |
| `cod_form.setup.health_rule_cod_fee_ignored` | Setup health (info), shown when an enabled COD-type rule has amount > 0 and `cod_fee_enabled` is false; links to `/features/cod-fees` | "Your partial payment rules include a COD fee. The COD Form uses the fee from COD fees settings, which is currently off." |
| `cod_form.setup.health_otp_unavailable` | Setup health (warning), `count` = `cf_otp_bypassed` events in the last 24 h | "OTP could not be sent for {count} orders in the last 24 hours. Those orders were placed without verification. Check your message balance." |
| `cod_form.limit_cod.postal_help` | Limit COD, under both postal fields | "Prefixes (4000*) and ranges (1000-1999) work in the COD Form only. Shopify checkout matches exact codes." |
| `cod_form.limit_cod.allow_list_warning` | Limit COD, warning banner when the **allow** list has a prefix or range entry | "Prefixes and ranges are not read by Shopify checkout yet. With this list, checkout shows COD only for the exact codes in it." |
| `cod_form.limit_cod.allow_list_critical` | Limit COD, critical banner when the allow list has **no** exact code (also health `zip_allow_list_no_exact`) | "This list has no exact postal codes, so Shopify checkout will hide COD for every buyer. Add exact codes, or turn on "COD only through the form"." |
| `cod_form.limit_cod.free_plan_note`, `cod_form.cod_fees.free_plan_note` | Limit COD and COD fees screens on the Free plan | "On the Free plan this applies to COD Form orders. Upgrade to Pro to apply it at Shopify checkout too." |
| `cod_form.summary.flagged_body` / `_cta` | Summary + Setup usage card for a paid shop in state `flagged` | "You have passed {cap} form orders this month. Your form keeps working." / upgrade button to the next plan |
| `cod_form.billing.overage_line` | Billing, only when the resolved `overage_rate` is set | "After {cap} form orders: ${rate} per extra order" |

Saving is never blocked by the postal warnings. The checkout payment function is not changed in this release (prefix/range support and the PRE-3 key go out with the next extension deploy, from the WS4 snippets). Detection of prefix/range entries in the admin uses the same syntax rules as `Engine::PostalMatcher` (E.2). The existing Pro gate of the COD fees and Limit COD screens for Shopify checkout is unchanged. A gated feature shows a locked card with the plan name and an upgrade button; after a downgrade the saved configuration is kept but no longer sent to the storefront.

---

## I. Tracking, integrations, abandonment, analytics

### I.1 Funnel events (ANL-1, ANL-3)

`FormFunnelEvent::EVENT_TYPES` gains (prefix `cf_` keeps them apart from Express's `form_view` / `checkout_initiated`):

```
cf_button_view cf_form_open cf_first_input cf_shipping_selected cf_submit_attempt cf_submit_error
cf_order_created cf_form_close cf_prepaid_redirect cf_partial_handoff cf_prepaid_order
cf_otp_sent cf_otp_verified cf_otp_bypassed cf_offer_view cf_offer_accept cf_downsell_shown cf_downsell_accept
cf_upsell_view cf_upsell_accept cf_recovery_open cf_blocked cf_fallback cf_client_error
```

| Written by | Events |
| --- | --- |
| Server (authoritative, never accepted from the browser) | `cf_form_open` (session), `cf_order_created`, `cf_prepaid_redirect`, `cf_partial_handoff`, `cf_prepaid_order`, `cf_otp_sent`, `cf_otp_verified`, `cf_otp_bypassed`, `cf_upsell_accept`, `cf_blocked`, `cf_recovery_open` |
| Browser via `POST /api/form/events` | `cf_button_view`, `cf_first_input`, `cf_shipping_selected`, `cf_submit_attempt`, `cf_submit_error`, `cf_form_close`, `cf_offer_view`, `cf_offer_accept`, `cf_downsell_shown`, `cf_downsell_accept`, `cf_upsell_view`, `cf_fallback`, `cf_client_error` |

- `session_token` column = session `public_id` (or `client_id` for pre-session events). `metadata` (max 20 keys) always carries `country`, `device`, `source`, `form_id`; plus `product_ids` (array), `utm_campaign`, `offer_id`, `ab` (`{"test_id": "variant"}`), `value_cents`, `currency`, `reason`, `test` where relevant. Test sessions are stored with `"test": true` and excluded from every aggregate.
- `cf_button_view` is high volume and is **not** stored as rows: `CodForm::EventIngestService` does `Redis HINCRBY codf:bv:<shop_id>:<yyyy-mm-dd> "<country>|<device>|<product_id>" 1` (key TTL 3 days); the rollup job folds the hash into `cod_form_daily_stats`.
- `cf_client_error` is forwarded to Sentry and not stored.
- Rollup: `CodForm::Analytics::RollupJob` (sidekiq-cron, hourly at minute 7, queue `low`) recomputes today and yesterday (shop time zone) per shop with activity into `cod_form_daily_stats` for each dimension of B.17. `CodForm::Analytics::PurgeJob` (daily) deletes `cf_*` rows older than 90 days in batches of 5 000 (ANL-5). Both are added to `config/schedule.yml`.
- `CodFormAdmin::AnalyticsController` reads rollups for ranges/filters they can answer and raw events otherwise (B.17). Pure aggregation helpers live in `app/services/cod_form/analytics/` (`funnel.rb`, `rollup.rb`), plain Ruby with tests (owner WS8).
- The existing `AnalyticsController#form_funnel` (Express) is not changed.

### I.2 Pixel events and shared ids (TRK-1..3, TRK-7, TRK-8)

| Moment | Event id (browser and server use the same) | Meta | TikTok | GA4 / Google Ads | Snapchat | Pinterest |
| --- | --- | --- | --- | --- | --- | --- |
| Form open | `codkf_<session_id>_ic` | `InitiateCheckout` | `InitiateCheckout` | `begin_checkout` | `START_CHECKOUT` | `checkout` is not sent; `addtocart` |
| Order created (`purchase_event: "purchase"`) | `order_<order_id>_purchase` (F20) | `Purchase` | `CompletePayment` (`PlaceAnOrder` when `config.tiktok_event == "place_order"`) | `purchase` / Ads conversion `AW-…/label` with `transaction_id = order_id` | `PURCHASE` | `checkout` |
| Order created (`purchase_event: "lead"`) | `order_<order_id>_lead` | `Lead` | `SubmitForm` | `generate_lead` | `SIGN_UP` | `lead` |

`CodForm::Tracking::EventMap` holds this table. Browser: chunks `pixels-*.js` (G.8) use `eventID` (Meta), `event_id` (TikTok), `transaction_id` (Google), `client_dedup_id` (Snap), `event_id` (Pinterest). After an order the core also calls `window.Shopify?.analytics?.publish("cod_order_placed", response.web_pixel)` (TRK-5, F21) — this is what fires the existing web pixel's Google Ads conversion; the form's own Google chunk therefore sends only GA4 `purchase` plus Ads conversions for `tracking_pixels` rows of platform `google_ads` whose id differs from `Setting#google_conversion_id`.

### I.3 Server side — `app/services/cod_form/tracking/` (owner WS8)

| Class | Notes |
| --- | --- |
| `PixelResolver.for(shop, product_ids:, collection_ids:)` | enabled `tracking_pixels` matching the targeting, plus the implicit Meta pixel from `Setting` (B.10); applies gates (`first_pixel`, `extra_pixels`, `pixels_p3`) and the limit of 5 per platform. |
| `ServerDispatchJob.perform_async(session_id, moment)` | queue `default`, retry 3. Loads the session + pixels, skips when consent denies marketing, calls the clients below. Errors go to `Rails.logger.warn` and, above 5 failures per shop per hour, one Slack alert (NFR-7: error-only). |
| `MetaClient.send_event(pixel:, event:)` | `POST https://graph.facebook.com/v19.0/<pixel_id>/events` — payload built like `NetworkServices::MetaConversionService#sync_event` (hashed `em`, `ph`, `external_id`, `fbp`, `fbc`, `client_ip_address`, `client_user_agent`, `event_source_url`, `custom_data` value/currency/content_ids). For the implicit `Setting` pixel and a `purchase` moment it calls the existing `NetworkServices::MetaConversionService.call_purchase(order, setting, meta_click_data:, client_context:, campaign_attribution:)` so behaviour and event id stay identical. |
| `TiktokClient.send_event` | `POST https://business-api.tiktok.com/open_api/v1.3/event/track/`, header `Access-Token`, body `{event_source: "web", event_source_id: pixel_code, data: [{event, event_time, event_id, user: {phone: sha256, email: sha256, ttp, ttclid, ip, user_agent}, properties: {value, currency, contents, content_type: "product"}, page: {url}}]}`. |
| `Ga4Client.send_event` | Measurement Protocol `POST https://www.google-analytics.com/mp/collect?measurement_id=<id>&api_secret=<token>` with `client_id` from `tracking.ga_client_id`. |
| `GoogleAdsClient` | calls the existing `NetworkServices::GoogleConversionService.call_purchase(order, setting, gclid:)` (TRK-7). Note: the unused `report_purchase_to_google_if_configured` in `cod_order_create_service.rb:147-169` (its only call, line 73, is commented out) passes `gbraid:`, `wbraid:`, `gad_campaignid:`, `gad_source:`, which `call_purchase(order, setting, gclid: nil)` does not accept — re-enabling that line as it stands would raise `ArgumentError`. Pass `gclid:` only. |
| `SnapchatClient.send_event` | `POST https://tr.snapchat.com/v3/<pixel_id>/events?access_token=…`. |
| `PinterestClient.send_event` | `POST https://api.pinterest.com/v5/ad_accounts/<ad_account_id>/events`, bearer token. |

`CodForm::PostOrderJob.perform_async(session_id)` (queue `default`): `ServerDispatchJob` for `purchase`; marketing consent (`customerSmsMarketingConsentUpdate` / `customerEmailMarketingConsentUpdate`, FRM-17); `Integrations::GoogleSheetsAppendJob`; `Integrations::KlaviyoClient` / `OmnisendClient` order events; overage billing check (J.2). Each step is independent and rescued.

`CampaignAttributionHelper::ALLOWED_KEYS` gains `ttclid`, `sccid`, `epik` (additive; owner WS8).

### I.4 Abandonment and recovery (ABN-1..4) — `app/services/cod_form/abandonment/` (owner WS8)

- `CodForm::Abandonment::SweepJob` (sidekiq-cron every 5 minutes, queue `low`): sessions with `status IN ('open','otp_pending','blocked')`, `order_id IS NULL`, `updated_at < now − general.abandonment.delay_minutes` (default 15), a phone or email in `contact`, not test, shop setting `abandonment.enabled` and (`Setting#abandoned_cart_enabled` or `ac_whatsapp`) — abandoned forms are active only when the shop already has abandoned-cart messages on. The 15-minute delay is fixed in the UI for now; draft order per abandoned form and recovery discount are off by default. For each: `MarkAbandonedService`.
- `MarkAbandonedService.call(session)`: sets `status = 'abandoned'`, `abandoned_at`, `recovery_token`; builds `recovery_url = "https://<primary domain>/?codk_recover=<token>"` (product sessions use the product URL from `tracking.page_url` with the parameter appended); creates the **anchor** `AbandonedCart` exactly like `Webhooks::ProcessInboundEventJob#upsert_anchor` (F13): `checkout_id: "codf_<public_id>"`, `is_anchor: true`, `source: "cod_form"`, `url: recovery_url`, `phone`, `country_code`, `notif_type: "WHATSAPP"`, `total_price`, `name`, `featured_image`, `source_payload: {session, items, totals}`; then, for non-BSP shops, the legacy stage rows + `ShopifyJobs::AbandonedCartJob.perform_in` (same logic as `schedule_legacy_stages`, lines 159-203); BSP shops are picked up by `Whatsapp::ScheduleAbandonedCartRemindersJob` because `cod_form` is added to `AbandonedCart::WEBHOOK_SOURCES`. Optional `Shopify draft order` (ABN-3): `draftOrderCreate` with tag `codking_abandoned_form` when `general.abandonment.create_draft_order`.
- Recovery: the loader sees `codk_recover`, opens the form with `recovery_token`; the session endpoint creates a **new** session with `source: "recovery"`, `prefill` from the abandoned one, and the optional recovery discount (`general.abandonment.recovery_discount`, applied as a downsell-type order discount); event `cf_recovery_open`. On order, the old session becomes `recovered` and the anchor's `notes = 'Recovered'`.
- Klaviyo / Omnisend (ABN-4, INT-2): `Integrations::KlaviyoClient.track(shop, event: "COD Form Abandoned" | "COD Form Order Placed", profile:, properties:)` → `POST https://a.klaviyo.com/api/events/` (`Authorization: Klaviyo-API-Key …`, `revision` header); `Integrations::OmnisendClient.track` → `POST https://api.omnisend.com/v5/events` (`X-API-KEY`).

### I.5 Google Sheets (INT-1) — `app/services/cod_form/integrations/google_sheets/`

- OAuth: `CodFormAdmin::GoogleOauthController#auth_url` builds `https://accounts.google.com/o/oauth2/v2/auth` (scopes `https://www.googleapis.com/auth/spreadsheets`, `https://www.googleapis.com/auth/drive.file`, `access_type=offline`, `prompt=consent`, `state` = signed (`Rails.application.message_verifier("cod_form_google")`) `{shop_id, exp}`); `#callback` (public route, no session token — the state signature is the authentication) exchanges the code at `https://oauth2.googleapis.com/token`, stores tokens in `cod_form_integrations.credentials`, and renders a page that closes the popup. ENV: `GOOGLE_SHEETS_CLIENT_ID`, `GOOGLE_SHEETS_CLIENT_SECRET`. Plain `Net::HTTP`/`HTTParty` (already a dependency); no new gem.
- `Client` (`refresh!`, `list_spreadsheets`, `append_row(spreadsheet_id, sheet_name, values)` → `POST https://sheets.googleapis.com/v4/spreadsheets/<id>/values/<sheet>!A1:append?valueInputOption=USER_ENTERED`).
- `GoogleSheetsAppendJob.perform_async(session_id)` — queue `default`, `sidekiq_options retry: 8` (exponential back-off covers "near real time with retries"); idempotent per order via a `Rails.cache` key `codf:gs:<order_id>` written after success.
- Column keys available for mapping: `order_name, order_id, created_at, first_name, last_name, phone, email, address1, address2, city, province, zip, country, items, quantity, subtotal, discount, shipping, cod_fee, total, currency, shipping_rate, discount_code, utm_source, utm_medium, utm_campaign, note, custom:<field key>`.
- Whole feature behind gate `google_sheets` and `ENV["GOOGLE_SHEETS_CLIENT_ID"]` present; otherwise the card shows "not available".

### I.6 Other integration points

- **Google address autocomplete (INT-3):** merchant key in `general.autocomplete.google_api_key`; the chunk loads `https://maps.googleapis.com/maps/api/js?key=…&libraries=places` on focus of `address1`, restricted to the selected country, and fills `address1`, `city`, `province`, `zip`.
- **RabbitPay hook (PRE-6):** interface only — G.4 (`codking:pay_online`, `registerPayOnlineHandler`) and `CodForm::Integration` provider `rabbitpay` (`config: {"enabled": bool}`) so the session can tell the form a handler is expected (`features.pay_online_handler`). No RabbitPay code.
- **Privacy webhooks (NFR-8):** `CodForm::PrivacyService` — `redact_customer(shop, phone:, email:)` blanks `contact`, `address`, `ip`, `custom_fields` on matching sessions and deletes matching `cod_block_entries` and `cod_form_rejections`; `export_customer(...)` returns the stored data; `redact_shop(shop)` deletes every `cod_*` row of the shop. `ScriptController#delete_data` (F32) gains one guarded call to it (owner WS8).
- **OTP unavailable notice:** `CodForm::CapNotifyJob`'s sibling `CodForm::OtpUnavailableNotifyJob.perform_async(shop_id)` (enqueued by `OtpService` on a bypass) sends `CodFormMailer.otp_unavailable_notice(shop_id)` at most once per 24 h per shop (`Rails.cache` key `codf:otp_unavail_mail:<shop_id>`).
- **Cap notices (CAP-8):** `CodForm::CapNotifyJob` → `CodFormMailer.usage_notice(shop_id, level)` (80 / 100, once per period via `form_order_usages.notified_*_at`) and the in-app notice shown by `UsageCard` / `CodFormSummaryCard` from `GET /cod_form/usage`.
- **PRE-3 "COD only through the form":** `general.cod_only_through_form` is passed into the payment customization function's configuration by `ShopifyServices::PaymentCustomizationService` as a new key `hideCodAtCheckout`; the function change (hide the COD method when the key is true, and postal prefix/range matching) is **not** made in this release: WS4 delivers it only as a snippet (`docs/cod-form/snippets/ws4-payment-function.md`) for the next extension deploy. Until then the toggle is saved and passed but has no effect at checkout; the Setup screen says so next to it. Off by default.

---

## J. Feature gates, caps, internal admin

### J.1 Feature keys (`feature_gates` seed; CAP-10)

| `feature_key` | `min_tier` | Covers |
| --- | --- | --- |
| `cod_form_core` | free | form, buttons, shipping rates, COD fee and COD rules on form orders (every plan) |
| `quantity_offers` | free | OFF-1..4, including the product-page widget |
| `block_lists` | free | FRD-1 |
| `velocity_limits` | free | FRD-2, FRD-3 |
| `basic_analytics` | free | ANL-1, ANL-2 |
| `first_pixel` | free | first pixel per platform |
| `abandonment_recovery` | free | ABN-1..3 (messages are billed as today) |
| `discount_code_field` | free | FRM-16 |
| `custom_fields` | free | FRM-13..15 |
| `preset_a` | free | BTN-12 |
| `templates` | free | FRM-21 |
| `embedded_mode` | free | FRM-20 |
| `order_bumps` | free | OFF-5, OFF-6 |
| `downsell` | free | OFF-7 |
| `upsell` | free | OFF-10 |
| `google_sheets` | free | INT-1 |
| `extra_pixels` | free | TRK-2 multiple pixels (max 5 per platform) |
| `pixels_p3` | free | Snapchat, Pinterest, product-specific pixels (TRK-8) |
| `address_autocomplete` | pro | INT-3 |
| `threshold_offers` | pro | OFF-11 |
| `multiple_forms` | pro | FRM-22 (1 form without it, up to 5 with it) |
| `advanced_analytics` | pro | ANL-4 |
| `klaviyo_omnisend` | pro | INT-2, ABN-4 |
| `risk_based_otp` | pro | OTP-7 |
| `rto_gating` | pro | RUL-3 |
| `branding_removal` | pro | hide "Powered by COD King" (same rule as `UiCustomizationPlanGuard`; neither that file nor `Sidekick::PlanCatalog` is edited) |
| `ab_tests` | enterprise | OFF-12 |

All rows are seeded with `enabled: true`. Evaluation: `CodForm::Gates.for(shop)` (`app/services/cod_form/gates.rb`, owner WS3) → `Engine::FeatureGates.map(tier: Sidekick::PlanCatalog.tier_for(shop), gates: FeatureGate rows (cached 60 s), overrides: shop_config.feature_overrides)`. The admin UI reads it from `bootstrap.gates`; the server enforces it in the admin API (402) and when building storefront config (a gated-off feature is simply absent).

### J.2 Cap (CAP-1..9)

- Period: `CapService.period_for(shop, Time.current)` = `Time.current.in_time_zone(ScheduledShopReport.extract_iana_from_shop_timezone(shop.owner_timezone)).strftime("%Y-%m")` (falls back to UTC for an unknown zone).
- Resolution: `Engine::CapResolver.resolve` (E.13). Country groups for a shop: active groups whose `country_codes` include `shop.country_code`.
- Seed (`plan_limits` + `cod_form_country_groups`; every value stays editable in the internal admin):

  | `scope_type` | `scope_key` | `plan_tier` | `monthly_cap` | `at_cap_behaviour` | `grace_orders` | `overage_rate` |
  | --- | --- | --- | --- | --- | --- | --- |
  | `plan` | `free` | – | 60 | `grace` | 10 | null |
  | `plan` | `pro` | – | 500 | `flag_only` | null | null |
  | `plan` | `enterprise` (tier includes `india_budget`, F27) | – | 10000 | `flag_only` | null | null |
  | `plan` | `enterprise_plus` | – | null (unlimited) | null | null | null |
  | `country_group` | id of "Launch markets" (HU, CO, RS, DO, MA, PE, PK) | null (all tiers) | null (unlimited) | null | null | null |

  Global setting: `at_cap_behaviour: "fallback"`, `grace_orders: 0`, `usage_notice_thresholds: [80, 100]`. Launch-market status follows `shops.country_code`. Free-shop timeline: notices at 48 and 60 orders; orders 61–70 still go through the form (`grace`); from order 71 the COD button opens Shopify checkout until the next calendar month. A paying shop is only ever `flagged`; its form never stops.
- States: `ok` (`orders < cap`), `fallback` (behaviour `fallback` and `orders ≥ cap`, or behaviour `grace` and `orders ≥ cap + grace_orders`), `grace`, `flagged` (behaviour `flag_only`). Fallback is enforced at session and at submit, and pushed to the storefront through `cap_fallback` in the metafield.
- Overage (CAP-9) is built but **switched off**: no `overage_rate` is seeded (planned value when product turns it on: USD 0.05 per extra order on Pro and Enterprise, by editing the row). When a paid shop's order is beyond the cap and the resolved `overage_rate` is set, `PostOrderJob` increments `over_cap_count`; `CodForm::OverageBillingJob` (sidekiq-cron daily 02:30 UTC, queue `administration`) bills `(over_cap_count − overage_billed_count) × overage_rate` with `ShopifyServices::UsageChargeApplyService.call(shop.shopify_domain, amount, description: "COD Form extra orders (<period>)")` and adds the billed count on success (`capped_amount_exhausted` is logged and retried next day).

### J.3 Internal admin (Administrate) — owner WS1

Dashboards `app/dashboards/cod_form/{plan_limit,country_group,feature_gate,global_setting,shop_config,order_usage,admin_audit}_dashboard.rb` (classes `CodForm::PlanLimitDashboard`, …); controllers `app/controllers/admin/cod_form/{plan_limits,country_groups,feature_gates,global_settings,shop_configs,order_usages,admin_audits}_controller.rb` (`Admin::CodForm::PlanLimitsController < Admin::ApplicationController`; inside these classes always write `::CodForm::…` for the models, because `Admin::CodForm` shadows the top-level module). Each controller sets `::CodForm::Current.actor = "admin:#{ENV['ADMIN_USER']}"` and `.ip` in a `before_action` (F29).

Routes snippet (inside the existing `namespace :admin do` block, `config/routes.rb:37`):

```ruby
namespace :cod_form do
  resources :plan_limits
  resources :country_groups
  resources :feature_gates
  resources :global_settings, only: %i[index show edit update]
  resources :shop_configs,   only: %i[index show edit update]     # editable: module_access, feature_overrides, storefront_mode
  resources :order_usages,   only: %i[index show]
  resources :admin_audits,   only: %i[index show]
end
```

`ShopConfigDashboard` form attributes: `module_access` (select), `feature_overrides` (JSON text), `storefront_mode`. `country_codes`, `feature_overrides` use a small custom Administrate field `app/fields/json_text_field.rb` (textarea ↔ JSON) with its three view partials under `app/views/fields/json_text_field/`.

---

## K. Work breakdown and file ownership

### Rules for every developer

- Work only inside `/home/claude/work`.
- Never run git write commands (`git add`, `git commit`, `git checkout`, `git stash`, `git reset`, …).
- Do not edit files you do not own. If you need a change in someone else's file, deliver a snippet under `docs/cod-form/snippets/` (rule 2 below).
- Do not edit `extensions/cod-king-otp-extension/blocks/app-embed.liquid`.
- Do not add columns to `settings` (or to any existing table).
- Every Ruby file must pass `ruby -c`.
- Pure engines must have plain-minitest tests runnable without Rails: `ruby -Itest test/services/cod_form/engine/<name>_test.rb`.
- No PII in logs (no names, phones, emails, addresses, tokens, OTP codes).
- Money is integer cents everywhere (0.1).

Rules for every workstream:

1. Create or edit **only** the files listed for your stream. Never edit a file owned by another stream.
2. If you need a change in a file you do not own, write a snippet file `cod-confirm/docs/cod-form/snippets/<ws>-<file>.md` (exact text to insert + where) and stop there. The owner / integrator merges it.
3. Depend on other streams only through the names in K.9. Do not create stand-ins for classes owned by another stream outside your own test files.
4. No `git` writes. Ruby files must pass `ruby -c`. Engines and other pure classes must have plain minitest tests that run without Rails.
5. Phases: everything (P1 + P2 + P3) is built now; optional features are switched by gates and config, not by leaving code out.

### K.1 WS1 — database, models, internal admin

Creates:
- `db/migrate/20261003100100_create_cod_form_shop_configs.rb`, `…100200_create_cod_forms.rb`, `…100300_create_cod_button_configs.rb`, `…100400_create_cod_shipping_rates.rb`, `…100500_create_cod_offers.rb`, `…100600_create_cod_offer_ab_tests.rb`, `…100700_create_cod_block_entries.rb`, `…100800_create_cod_form_sessions.rb`, `…100900_create_cod_form_rejections.rb`, `…101000_create_tracking_pixels.rb`, `…101100_create_form_order_usages.rb`, `…101200_create_plan_limits.rb`, `…101300_create_cod_form_country_groups.rb`, `…101400_create_feature_gates.rb`, `…101500_create_cod_form_global_settings.rb`, `…101600_create_cod_form_admin_audits.rb`, `…101700_create_cod_form_daily_stats.rb`, `…101800_create_cod_form_integrations.rb`, `…101900_seed_cod_form_defaults.rb`
- `app/models/cod_form/{shop_config,form,button_config,shipping_rate,offer,ab_test,block_entry,session,rejection,tracking_pixel,order_usage,plan_limit,country_group,feature_gate,global_setting,admin_audit,daily_stat,integration,current}.rb`
- `app/models/concerns/cod_form/admin_audited.rb`
- `app/dashboards/cod_form/*_dashboard.rb` (7), `app/controllers/admin/cod_form/*_controller.rb` (7), `app/fields/json_text_field.rb`, `app/views/fields/json_text_field/{_form,_show,_index}.html.erb`
- `test/models/cod_form/*_test.rb` (Rails tests, cannot run here; keep them small)
- `docs/cod-form/snippets/ws1-routes.md` (the `namespace :cod_form` block of J.3)

Edits: `app/models/shop.rb` (associations, B.19), `db/schema.rb` (hand-written `create_table` blocks matching the migrations — to be regenerated by `rails db:migrate` on a real environment).

Model methods other streams rely on: `CodForm::ShopConfig.for(shop)`, `#cod_form_mode?`, `#module_enabled?` (uses `GlobalSetting.current`), `#bump_version!` (increments `config_version`, enqueues `CodForm::MetafieldSyncJob`), `CodForm::Form.default_for(shop)`, `#publish!`, `CodForm::OrderUsage.increment!(shop_id:, period:, column:)`, `.for(shop_id, period)`, `CodForm::GlobalSetting.current`, `CodForm::Session#mark_ordered!(order)`, scopes `Offer.active_now`, `ShippingRate.active.ordered`, `BlockEntry.normalize(kind, value)`.

### K.2 WS2 — pure-Ruby engines and their tests

Creates: `app/services/cod_form/engine/{money,postal_matcher,cod_rules,visibility,shipping_rates,offers,offer_overlap,quote,cod_fee,fraud,phone,country_schema,partial_rules,session_token,defaults,form_config,form_validator,form_targeting,button_config,metafield_payload,feature_gates,cap_resolver,otp_policy,ab_test,thank_you,draft_order_builder,recovery}.rb`; `config/cod_form/countries.json`; `test/services/cod_form/engine/*_test.rb`, `test/services/cod_form/engine/all.rb`, `test/services/cod_form/engine/fixtures/{phone_cases,validation_cases,quote_cases,postal_cases}.json`.

Edits: none.

### K.3 WS3 — storefront API, order creation, security, routes

Creates:
- `app/controllers/api/form/{base,sessions,quotes,contacts,otp,orders,handoffs,upsells,events,geo}_controller.rb`
- `app/services/cod_form/{availability,origin_guard,rate_limiter,errors,gates,catalog_service,offer_resolver,discount_code_service,risk_service,fraud_adapter,quote_service,tax_service,cap_service,customer_resolver,otp_service,order_service,handoff_service,upsell_service,order_webhook_hook}.rb`, `app/services/cod_form/adapters/{rules_adapter,cod_fee_adapter,partial_rules_adapter,money_format_adapter}.rb`
- `app/services/shopify_services/order_edit_add_line_service.rb`
- `app/workers/cod_form/{create_order_job,session_purge_job}.rb`
- `config/initializers/cod_form.rb` (`to_prepare` hooks: `Setting.after_commit` → metafield re-sync when a COD-rule or COD-fee column changed; ENV validation)
- `lib/cod_form/geo/*.json` (provinces for HU, CO, RS, DO, MA, PE, PK, IN from Shopify's country data; `cities` only where a dataset is approved)
- `test/services/cod_form/*_test.rb` for the pure parts (origin host matching, rate-limit key building)
- `docs/cod-form/snippets/ws3-schedule.yml.md` (`CodForm::SessionPurgeJob`, daily)

Edits (sole owner): `config/routes.rb` (own routes of D.13 **and** merges the snippets of WS1, WS6), `config/initializers/rack_attack.rb` (D.0.4), `config/initializers/filter_parameter_logging.rb`, `app/services/shopify_services/cod_order_create_service.rb` (F.4), `app/controllers/api/cod_orders_controller.rb` (D.12: origin guard in log-only mode; remove nothing), `app/workers/order_confirmation_create_job.rb` (F.5, the three insertions only).

### K.4 WS4 — embed, loader, button, widget, build

Creates (extensions repo): `extensions/cod-king-otp-extension/blocks/cod-form-embed.liquid`; `storefront/cod-form/{package.json,build.mjs,size-limits.json,README.md}`; `storefront/cod-form/src/shared/*`; `storefront/cod-form/src/loader/*`; `storefront/cod-form/src/extras/*`; `storefront/cod-form/src/widget/*`; `storefront/cod-form/test/loader/*.test.mjs`.
Creates (backend repo): `docs/cod-form/snippets/ws4-app-embed.liquid.md` (guard for the Express embed, G.2), `docs/cod-form/snippets/ws4-payment-function.md` (PRE-3), `docs/cod-form/PAGE_BUILDERS.md` (BTN-10).
`build.mjs` discovers entries by convention so WS5 never edits it: `src/chunks/*.{js,jsx}` → `codk-form-<basename>.js`, `src/i18n/*.json` → `codk-form-i18n-<basename>.js`, `src/core/index.js` → `codk-form-core.js`. `size-limits.json` holds the table of G.10 as `{"<glob>": <bytes>}` plus the two composite limits `default_path` (5120) and `with_extras` (6656). `harness/render-embed.mjs` is owned by WS5; the build imports it to measure the inline part.
Edits: none (`blocks/app-embed.liquid` is off limits). Generated files `extensions/cod-king-otp-extension/assets/codk-form-*` are produced by the build and committed by the integrator.

### K.5 WS5 — Preact form, chunks, texts, harness

Creates (extensions repo): `storefront/cod-form/src/core/**`, `storefront/cod-form/src/chunks/**`, `storefront/cod-form/src/i18n/{en,hi,ar,fr,es,hu,sr,ur}.json`, `storefront/cod-form/scripts/export-texts.mjs`, `storefront/cod-form/test/core/*.test.mjs`, `storefront/cod-form/test/fixtures/*` (copies of WS2's fixtures), `storefront/cod-form/harness/**`.
Creates (backend repo): `config/cod_form/default_texts.json` (generated by `export-texts.mjs`).
Imports from `src/shared/*` (owned by WS4) by the export names in G.1; must not edit them.

### K.6 WS6 — admin API

Creates: `app/controllers/cod_form_admin/{base,bootstrap,setup,buttons,forms,shipping_rates,offers,ab_tests,fraud,block_entries,rejections,pixels,integrations,google_oauth,analytics,usage,preview_frames}_controller.rb`; `app/views/cod_form_admin/preview_frames/show.html.erb`, `app/views/cod_form_admin/google_oauth/callback.html.erb`; `app/services/cod_form/{enable_service,metafield_sync_service,embed_status_service,domain_sync_service,merchant_audit,shipping_csv_importer,setup_health}.rb`; `app/workers/cod_form/{metafield_sync_job,metafield_sync_all_job,domain_sync_job}.rb`; `docs/cod-form/snippets/ws6-routes.md` (D.16, both the API scope and the page routes).
Edits: `app/services/shopify_services/payment_customization_service.rb` (adds `hideCodAtCheckout`, I.6).
`AnalyticsController` here only shapes the response; the queries come from WS8's `CodForm::Analytics::Query` (K.9).

### K.7 WS7 — admin React screens

Creates: everything under `app/javascript/packs/Pages/CodForm/` (H.4).
Edits (sole owner): `Pages/SettingsHub/registry.js`, `Pages/SettingsHub/icons.jsx`, `Pages/SettingsHub/SettingsHub.jsx`, `Pages/Home.jsx`, `Components/AnalyticsDashboardTabs.jsx`, `Components/Summary.jsx`, `Components/Integrations/IntegrationsHub.jsx`, `Components/PartialPayment/PartialPayment.jsx`, `Components/Billing.jsx`, `Components/CODShowHide.jsx`, `Components/CODFeesSettings.jsx`, `Components/CODFeesSettingsNew.jsx`, `Components/QuickOnboardingV2.jsx`, the OTP / UI-customization screens that get `ExpressOnlyBanner`, and `config/localeJson/en.json`.

### K.8 WS8 — tracking, integrations, abandonment, analytics, jobs

Creates: `app/services/cod_form/tracking/{event_map,pixel_resolver,meta_client,tiktok_client,ga4_client,google_ads_client,snapchat_client,pinterest_client}.rb`; `app/services/cod_form/integrations/{klaviyo_client,omnisend_client}.rb`, `app/services/cod_form/integrations/google_sheets/{client,row_builder}.rb`; `app/services/cod_form/abandonment/{mark_abandoned_service,recovery_service}.rb`; `app/services/cod_form/analytics/{funnel,rollup,query}.rb`; `app/services/cod_form/{event_ingest_service,funnel_logger,privacy_service}.rb`; `app/workers/cod_form/{post_order_job,cap_notify_job,otp_unavailable_notify_job,overage_billing_job}.rb`, `app/workers/cod_form/tracking/server_dispatch_job.rb`, `app/workers/cod_form/integrations/google_sheets_append_job.rb`, `app/workers/cod_form/abandonment/sweep_job.rb`, `app/workers/cod_form/analytics/{rollup_job,purge_job}.rb`; `app/mailers/cod_form_mailer.rb`, `app/views/cod_form_mailer/{usage_notice,otp_unavailable_notice}.html.erb`; `test/services/cod_form/analytics/*_test.rb`, `test/services/cod_form/tracking/event_map_test.rb` (plain minitest).
Edits (sole owner): `app/models/form_funnel_event.rb`, `app/models/abandoned_cart.rb`, `app/services/campaign_attribution_helper.rb`, `app/controllers/script_controller.rb` (`delete_data` → `CodForm::PrivacyService`), `config/schedule.yml` (own jobs + WS3's snippet), `config/locales/en.yml` (`cod_form_mailer.*`).

### K.9 Cross-stream contracts (call these names; the owner implements them)

| Name | Signature | Owner | Used by |
| --- | --- | --- | --- |
| `CodForm::ShopConfig.for` | `(shop) → ShopConfig` | WS1 | all |
| `CodForm::Engine::*` | section E | WS2 | WS3, WS6, WS8 |
| `CodForm::Availability.call` | `(shop) → {available: bool, fallback: String\|nil}` | WS3 | WS6 |
| `CodForm::Gates.for` | `(shop) → {"key" => {"allowed" => bool, "min_tier" => String}}` | WS3 | WS6, WS8 |
| `CodForm::CapService.state` / `.period_for` | `(shop) → Hash` / `(shop, time) → "YYYY-MM"` | WS3 | WS6, WS8 |
| `CodForm::RulesAdapter.from_setting` | `(setting) → E.3 rules hash` | WS3 | WS6 |
| `CodForm::CatalogService.shop_info` | `(shop) → {"currency","taxes_included","money_format"}` | WS3 | WS6 |
| `CodForm::MetafieldSyncJob.perform_async` | `(shop_id)` | WS6 | WS1, WS3 |
| `CodForm::MerchantAudit.record` | `(shop, field, old_value, new_value)` | WS6 | WS6 |
| `CodForm::FunnelLogger.log` | `(shop_id:, session_token:, type:, meta: {}, at: Time.current)` | WS8 | WS3 |
| `CodForm::EventIngestService.call` | `(shop:, session:, client_id:, events:, request_meta:)` | WS8 | WS3 |
| `CodForm::PostOrderJob.perform_async` | `(session_id)` | WS8 | WS3 |
| `CodForm::Tracking::ServerDispatchJob.perform_async` | `(session_id, moment)` — `moment` ∈ `"initiate_checkout"`, `"purchase"` | WS8 | WS3 |
| `CodForm::Tracking::PixelResolver.for` | `(shop, product_ids:, collection_ids:) → [pixel hashes]` | WS8 | WS3 (session response) |
| `CodForm::CapNotifyJob.perform_async` | `(shop_id, period)` | WS8 | WS3 |
| `CodForm::OtpUnavailableNotifyJob.perform_async` | `(shop_id)` | WS8 | WS3 |
| `CodForm::Abandonment::RecoveryService.prefill` | `(shop, recovery_token) → Hash\|nil` | WS8 | WS3 |
| `CodForm::Analytics::Query` | `.summary(shop, from:, to:, filters:)`, `.breakdown(shop, by:, from:, to:)`, `.export_rows(...)` | WS8 | WS6 |
| loader ↔ core | `core.open(ctx)`, `core.preload(opts)`, `core.preview(payload)`; `ctx` in G.3 | WS5 exports, WS4 calls | |
| shared JS | exports listed in G.1 `shared/` | WS4 | WS5 |

### K.10 Integration order

1. WS1 + WS2 merge first (no dependencies). 2. WS3, WS6, WS8 (backend) — the integrator merges `ws1-routes.md`, `ws6-routes.md` into `config/routes.rb` and `ws3-schedule.yml.md` into `config/schedule.yml`. 3. WS4 + WS5: `npm run build` in `storefront/cod-form`, commit `assets/codk-form-*` and `config/cod_form/default_texts.json`. 4. WS7. 5. Checks: `ruby -c` on every new/edited Ruby file; `ruby test/services/cod_form/engine/all.rb`; `node --test` in the storefront package; harness e2e; bundle size report.

ENV added: `COD_FORM_EXTENSION_UUID`, `COD_FORM_ASSET_BASE` (optional), `COD_FORM_ORIGIN_ENFORCE` (default enforce), `COD_FORM_ALLOW_LOCALHOST`, `COD_ORDERS_ORIGIN_ENFORCE` (default off), `GOOGLE_SHEETS_CLIENT_ID`, `GOOGLE_SHEETS_CLIENT_SECRET`. `APP_HOST` (existing) is the API base.

---

## L. Resolved product decisions

All 15 product questions are answered in `docs/cod-form/PM_DECISIONS.md` (3 Oct 2026), together with twelve further product defaults. Every decision is applied in this document; nothing is open. Where to find each:

| # | Decision (short) | Applied in |
| --- | --- | --- |
| 1 | Express shipping defect left as is; separate ticket | F.4 |
| 2 | COD fee = custom line item with the COD label | E.8, F.3 |
| 3 | Two embeds: warn, never block; guard only as a snippet | G.2, D.15, H.8 |
| 4 | Form orders get checkout-order messaging and verification | F.5 |
| 5 | Full COD always first and preselected in the payment step | D.2, E.11 |
| 6 | Only the COD fees setting applies; rule fee ignored | E.8, H.8 |
| 7 | Postal prefixes/ranges form-only, with warnings | E.2, H.8 |
| 8 | Caps: Free 60 + 10 grace, Pro 500 / Enterprise 10 000 flag-only, launch markets unlimited, overage off | J.2 |
| 9 | Gate table; COD fee and rules in the form on every plan | J.1, E.3, E.8, H.8 |
| 10 | Tax call only for tax-exclusive shops, on complete address | D.2 |
| 11 | `_codkDiscounts` attribute accepted for the prepaid path | G.3 |
| 12 | Bundle carts go to Shopify checkout (`bundle_cart`) | D.1, F.3, A.3 |
| 13 | No `read_shipping`; no Shopify shipping import | B.4, D.15 |
| 14 | 5 KB default path, 6.5 KB ceiling with extras | G.2, G.10 |
| 15 | OTP send failure → order proceeds unverified, merchant told | D.4, F.2, I.6, H.8 |

Follow-up tickets recorded by product (not part of this build): fix F3 with an announcement; payment-function update for prefixes/ranges and `hideCodAtCheckout`; move quantity-offer definitions into the discount function's configuration; review the launch-market unlimited override at the end of January 2027.

---

## M. Deviations from the spec and the planning brief (why, in one line each)

| Topic | Spec / brief | This design | Reason |
| --- | --- | --- | --- |
| Storefront mode field | one new column on `settings` | `cod_form_shop_configs.storefront_mode` | decision 3: no new `settings` columns |
| Order endpoint | harden `POST /api/cod_orders` | new `POST /api/form/orders`; legacy endpoint gets throttle + log-only origin check | decision 11: Express client must keep working |
| OTP endpoints | call existing endpoints with the session token | new `/api/form/otp/*` wrapping the same services | the existing endpoints cannot check a token without breaking Express |
| Funnel ingest | reuse `/form_funnel/ingest` | `/api/form/events` (batch, origin-checked) writing the same model | throttling, batching, counters for button views |
| Embed | one embed toggle, Liquid branches on mode | second embed block with its own toggle | decision 2: `app-embed.liquid` must not be edited now |
| Origin check | against `ShopDomain` | against `shops.primary_domain`, the myshopify domain and `allowed_origins` | F22 |
| Admin i18n file | `config/locales/en.yml` | `config/localeJson/en.json` | F25 |
| Shopify shipping import (SHP-7) | P2 requirement | not built | no `read_shipping` scope (product decision 13) |
| "Existing flows still fire" | assumed | needs the three-line hook in `OrderConfirmationCreateJob` | F9 |
| Visibility rules | in `cod_button_configs` | in `cod_form_shop_configs.general` | one record per admin screen |
| Rollup filters | country, product, device together | single-dimension rollups; combined filters from raw events (90 days) | bounded table size |

