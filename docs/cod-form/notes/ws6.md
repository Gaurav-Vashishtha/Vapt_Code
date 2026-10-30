# WS6 notes — admin JSON API, metafield publishing, embed status, setup health, CSV import

Scope: ARCHITECTURE.md D.14–D.16, C.1 (writer side), H.6 (preview frame), I.5 (OAuth endpoints), I.6 (PRE-3), K.6.

## Verification done here

The app cannot boot in this mirror (no DB, no gems), so:

- `ruby -c` passes on every file listed below.
- Plain minitest, no Rails — **77 runs, 425 assertions, 0 failures**:

  | Command | Covers |
  | --- | --- |
  | `ruby test/controllers/cod_form_admin/validators_test.rb` | every payload validator (general, fraud, shipping rate, offers, A/B tests, pixels, block entries, form-draft pre-check, templates, paging) |
  | `ruby test/services/cod_form/metafield_sync_service_test.rb` | `build_input` → `Engine::MetafieldPayload.build` equals the C.1.1 example **byte for byte** (keys and order); gates, `test_only`, `cap_fallback`, `features` |
  | `ruby test/services/cod_form/shipping_csv_importer_test.rb` | CSV parsing, row-level errors, limits, decimal formats |
  | `ruby test/services/cod_form/setup_health_test.rb` | health items, severities, checklist |
  | `ruby test/services/cod_form/admin_services_test.rb` | embed detection, audit diff / secret masking, domain cleaning, default-texts fallback, preview `asset_base` check |

- All controllers, services and workers were loaded together with stand-in base classes to catch class-body errors.
- **Not verified:** anything that needs Rails, the database or Shopify — the controller actions end to end, the session-token callbacks, the two GraphQL documents (see "Open issues").

## Files

Created:

```
app/controllers/cod_form_admin/
  base_controller.rb  bootstrap_controller.rb  setup_controller.rb  buttons_controller.rb  forms_controller.rb
  shipping_rates_controller.rb  offers_controller.rb  ab_tests_controller.rb  fraud_controller.rb
  block_entries_controller.rb  rejections_controller.rb  pixels_controller.rb  integrations_controller.rb
  google_oauth_controller.rb  analytics_controller.rb  usage_controller.rb  preview_frames_controller.rb
  validators.rb                                   (extra file, see deviation 1)
app/views/cod_form_admin/preview_frames/show.html.erb
app/views/cod_form_admin/google_oauth/callback.html.erb
app/services/cod_form/
  enable_service.rb  metafield_sync_service.rb  embed_status_service.rb  domain_sync_service.rb
  merchant_audit.rb  shipping_csv_importer.rb  setup_health.rb
app/workers/cod_form/
  metafield_sync_job.rb  metafield_sync_all_job.rb  domain_sync_job.rb
test/controllers/cod_form_admin/validators_test.rb
test/services/cod_form/{metafield_sync_service,shipping_csv_importer,setup_health,admin_services}_test.rb
docs/cod-form/snippets/ws6-routes.md             (D.16 verbatim + the two public routes + the page routes)
docs/cod-form/notes/ws6.md
```

Edited: `app/services/shopify_services/payment_customization_service.rb` (PRE-3, see "Payment function").

## Common rules (as built)

- Base: `CodFormAdmin::BaseController < AuthenticatedController`. `before_action :set_shop` is re-declared so it runs after the session-token callbacks (same idiom as `PartialRuleSetsController`), then `require_shop!`, `load_config` (`@config = CodForm::ShopConfig.for(@shop)`), `require_module!`.
- The body is read as a plain string-keyed Hash (`request.request_parameters.as_json`); nothing is permitted through strong params — every key is whitelisted and type-checked by a validator, unknown keys are dropped.
- Errors:

  | Status | Body |
  | --- | --- |
  | 402 | `{"error": "upgrade_required", "feature": "threshold_offers", "min_tier": "pro"}` |
  | 403 | `{"error": "module_disabled"}` (every endpoint except `bootstrap`) |
  | 404 | `{"error": "not_found"}` |
  | 422 | `{"error": "validation_failed", "errors": {"<path>": ["message"]}}` |
  | 422 | `{"error": "pixel_limit", "errors": {"platform": ["at most 5 pixels per platform"]}}` |

- Error paths: `general.order_total.max_cents`, `fraud.limits.ip.max_orders`, `conditions.provinces`, `config.tiers[1].value`, `variants[0].key`, `draft_config.blocks[3].type`. Engine errors (form, button) keep the engine's path and carry its **code** as the message, e.g. `{"button.style.bg": ["invalid_color"]}`, `{"draft_config.thank_you.url": ["invalid_url"]}`.
- A gate is checked only when a request turns a gated thing **on** (a downgrade keeps the saved configuration and never blocks saving the rest of the screen). A gated-off feature is left out of the storefront metafield.
- Every storefront-affecting write calls `@config.bump_version!`; every write records to `settings_change_audits` through `CodForm::MerchantAudit` (fields `cod_form.…`, `changed_by: "merchant"`).
- Lists that can be long are paged: `?page=N` → `"meta": {"page","pages","count"}`. 50 per page (`block_entries`, `rejections`, `ab_tests`, `offers` with `page`), 200 per page (`shipping_rates` with `page`). `shipping_rates` and `offers` without `page` return everything (offers capped at 500), as D.15 shows.

## Endpoints

All paths under `/cod_form`. "bump" = bumps `config_version` (metafield re-sync).

| Method + path | Gate | Notes |
| --- | --- | --- |
| `GET bootstrap` | – | D.15 shape. `usage` is `null` when `module_enabled` is false. `locales` = shop primary locale + `en`. |
| `GET setup` | – | D.15 shape. `embed` also has `legacy_theme_editor_url`, `checked_at`. `preview_url` is `null` until a preview token exists. |
| `PUT setup` | per key, see below | `{"general": {partial}}` → same as GET. bump. |
| `POST mode` | – | `{"mode"}` → `{"mode","enabled_at"}`. bump. |
| `POST setup/refresh_embed` | – | → `{"embed": {...}}`; also refreshes `allowed_origins`. |
| `POST setup/test_order` | – | → `{"preview_url"}`. bump. |
| `GET button` / `PUT button` | `preset_a` when switching to A | `{"preset","config"}`. bump. Sets checklist step `preset`. |
| `GET forms` | – | `{"items": [...]}`; creates the default form if the shop has none. |
| `GET forms/defaults` | – | `{"config","templates","texts","countries"}` |
| `POST forms` | `multiple_forms` (always, the first form is the default one), `templates` when `template_key` | 422 `errors.base` at 5 forms. bump. |
| `GET forms/:id` | – | D.15 keys + `status`, `position`, `has_unpublished_changes`. |
| `PUT forms/:id` | `custom_fields` when the draft gains its first custom field, `templates` when `template_key` changes | → form + `"warnings"` + `"publish_errors"`. bump only when `targeting` changed. |
| `POST forms/:id/publish` | – | 422 with `errors["draft_config.<path>"]` when the engine reports errors. bump (by `Form#publish!`). |
| `POST forms/:id/discard_draft` | – | → form |
| `POST forms/:id/duplicate` | `multiple_forms` | → new form (201), no targeting. |
| `POST forms/:id/make_default` | – | → `{"items"}`. bump. |
| `DELETE forms/:id` | – | archives → 204; default form → 422. bump. |
| `GET shipping_rates` | – | `{"items": [C.3]}` |
| `POST shipping_rates` / `PUT …/:id` / `DELETE …/:id` | – | C.3; PUT accepts partial bodies; DELETE → 204. bump. |
| `POST shipping_rates/reorder` | – | `{"ids": [...]}` → `{"items"}`. bump. |
| `POST shipping_rates/import_csv` | – | multipart `file`, `mode` → `{"created","errors":[{"row","message"}]}`. bump when rows were created. |
| `GET offers?type=&status=&page=` | – | `type` accepts `quantity`, `bump`, `upsell`, `downsell`, `threshold` and the plural URL words of H.4 (`bumps`, `upsells`, `downsells`, `thresholds`). Archived offers are not listed. |
| `GET offers/:id` | – | C.4 wrapper |
| `POST offers` / `PUT offers/:id` | `quantity_offers` / `order_bumps` / `upsell` / `downsell` / `threshold_offers` | → wrapper + `"warnings"`. bump. |
| `DELETE offers/:id` | – | archives → 204. bump. |
| `POST offers/:id/status` | type gate when activating | `{"status": "active"\|"paused"}` → wrapper + `"warnings"`. bump. |
| `GET ab_tests`, `GET ab_tests/:id` | – | B.6 shape; `:id` adds `"results"`. |
| `POST ab_tests`, `PUT ab_tests/:id`, `POST …/start` | `ab_tests` | PUT → 422 once started. start: bump. |
| `POST ab_tests/:id/stop` | – | optional `{"winner_key"}`. bump. |
| `DELETE ab_tests/:id` | – | 422 while running; else 204. |
| `GET fraud` / `PUT fraud` | `velocity_limits`, `risk_based_otp`, `rto_gating` | `{"fraud","otp","rto","shop_otp_enabled"}`; PUT accepts any subset, partial. bump. |
| `GET block_entries?kind=&q=&page=` | – | `{"items":[C.5],"meta"}` |
| `POST block_entries` | `block_lists` | → `{"created","skipped","invalid","over_limit"}` |
| `DELETE block_entries/:id` | – | 204 |
| `GET rejections?page=&reason=&stage=` | – | `{"items":[B.9 columns],"meta"}` |
| `GET pixels` | – | `{"items":[C.6]}` |
| `POST pixels` | `first_pixel` or `extra_pixels`, plus `pixels_p3` | bump. |
| `PUT pixels/:id` / `DELETE pixels/:id` | `pixels_p3` when targeting becomes `selected` | `platform` cannot change. bump. |
| `POST pixels/:id/test` | – | → `{"ok","response"}` (WS8 `CodForm::Tracking::TestEvent`) |
| `GET integrations` | – | all four providers, each with an extra `"available"` |
| `PUT integrations/:provider` | `google_sheets`, `klaviyo_omnisend` | `{"credentials","config"}` → item |
| `DELETE integrations/:provider` | – | 204 |
| `GET integrations/google_sheets/auth_url` | `google_sheets` | `{"url"}`; 422 `{"error":"not_available"}` without the ENV keys |
| `GET integrations/google_sheets/sheets[?spreadsheet_id=]` | `google_sheets` | `{"spreadsheets":[{"id","name"}]}`, plus `"sheet_names"` when `spreadsheet_id` is given; 422 `{"error":"google_reconnect_required"}`; 502 `{"error":"google_unavailable"}` |
| `GET analytics` | `basic_analytics` | body of `CodForm::Analytics::Query.summary` |
| `GET analytics/breakdown?by=` | `advanced_analytics` | body of `Query.breakdown` |
| `GET analytics/export(.csv)` | `advanced_analytics` | CSV attachment; optional `by=` |
| `GET usage` | – | D.15 shape |
| `GET /cod_form/preview_frame?asset_base=` | public | H.6 |
| `GET /cod_form/google/callback` | public (signed `state`) | I.5 |

Gated keys inside `general` (402 when turned on without the gate): `otp.mode = "risk_based"` → `risk_based_otp`; `rto.gating_enabled` → `rto_gating`; `branding.hide_powered_by` → `branding_removal`; `autocomplete.enabled` → `address_autocomplete`; `embedded.enabled` → `embedded_mode`; `discounts.code_field_enabled` → `discount_code_field`.

## Samples

`PUT /cod_form/setup`

```json
{"general": {"countries": ["HU", "CO"], "order_total": {"max_cents": 5000000}}}
```

→ 200, same body as `GET /cod_form/setup`:

```json
{
  "mode": "cod_form",
  "general": {"countries": ["HU", "CO"], "pages": {"product": true, "cart": true, "drawer": true, "quick_buy": false}, "…": "full B.1.1"},
  "setup_state": {"embed_seen_at": "2026-10-03T09:00:00Z", "preset_chosen_at": "2026-10-03T09:05:00Z"},
  "checklist": [{"key": "embed", "done": true}, {"key": "preset", "done": true}, {"key": "shipping_rate", "done": false}, {"key": "test_order", "done": false}],
  "health": [{"code": "no_shipping_rate", "severity": "critical", "count": null, "action_url": "/features/cod-form/shipping"}],
  "embed": {"enabled": true, "legacy_enabled": false, "checked_at": "2026-10-03T09:00:00Z",
            "theme_editor_url": "https://brand.myshopify.com/admin/themes/current/editor?context=apps&activateAppId=<uuid>/cod-form-embed",
            "legacy_theme_editor_url": "https://brand.myshopify.com/admin/themes/current/editor?context=apps"},
  "preview_url": "https://brand.com/?codk_preview=5f0c…",
  "usage": {"period": "2026-10", "orders": 12, "cap": 60, "state": "ok", "behaviour": "grace", "percent": 20}
}
```

422 example: `{"error": "validation_failed", "errors": {"general.order_total.max_cents": ["must not be less than the minimum"]}}`

`POST /cod_form/offers`

```json
{"offer_type": "quantity", "name": "Packs", "status": "active",
 "targeting": {"scope": "selected", "product_ids": ["8111", "8112"], "collection_ids": []},
 "config": {"title": {"default": "Buy more, save more"}, "layout": "cards",
            "tiers": [{"quantity": 1, "discount_type": "none"}, {"quantity": 2, "discount_type": "percentage", "value": 10, "preselected": true}]}}
```

→ 201 C.4 wrapper + `"warnings": [{"code": "collection_overlap", "offer_id": 6, "collection_ids": ["77"]}]` (codes: `collection_overlap`, `possible_collection_overlap`, `all_products_overlap`).
OFF-2: `422 {"errors": {"targeting": ["a product can be in only one active quantity offer (product ids: 8112)"]}}`. Limit: `422 {"errors": {"status": ["limit reached: at most 50 active quantity offers"]}}`.

`PUT /cod_form/forms/12` with `{"draft_config": {...}}` → form plus

```json
{"warnings": [{"path": "fields[3]", "code": "…"}], "publish_errors": [{"path": "thank_you.url", "code": "invalid_url"}]}
```

`POST /cod_form/block_entries` `{"kind": "phone", "values": ["+36 30 123 4567", "abc"]}` → `{"created": 1, "skipped": 1, "invalid": 1, "over_limit": 0}`

`POST /cod_form/shipping_rates/import_csv` (`mode=append`)

```
name,description,price,country,province,min_total,max_total
Budapest,1-2 days,990,HU,BU,,
Pest megye,2-3 days,1490.50,HU,HU-PE,,19999.99
Bad row,,abc,HU,,,
```

→ `{"created": 2, "errors": [{"row": 4, "message": "Price must be a number that is 0 or more."}]}`

## Behaviour worth knowing

**Metafield sync.** `MetafieldSyncJob.perform_async(shop_id)` is debounced: the first call of a burst schedules the real run 3 s later, further calls are dropped while it is pending. The job is also enqueued **without** a version bump (WS3's `CapService` on a cap state change, the `Setting` hook, the kill switch), so "nothing to do" is decided by a digest of the payload kept in `Rails.cache`, not only by `config_version > metafield_synced_version`. `MetafieldSyncJob.perform_async(shop_id, true, true)` runs immediately and forces the write; `MetafieldSyncAllJob.perform_async` does that for every shop that is in COD Form mode or has ever been synced. A failed Shopify write raises, so Sidekiq retries (3).

**`enabled` / `test_only`.** `enabled` = `CodForm::Availability.call(shop)[:available]`. When Availability reports `mode_off` (everything on except the mode) and the shop has a preview token, the payload is `enabled: true, test_only: true`, so the merchant can test before going live. The token is created by `POST setup/test_order` (or by the first enable); opening the Setup screen never creates one.

**First enable.** `EnableService.call`: default form (`Form.default_for`, published), default button config (`ButtonConfig.for`, preset B), `general` / `fraud` completed with defaults, `general.countries = [shops.country_code]` only on the first enable and only when empty, preview token, domain sync, bump. Disabling keeps everything and only flips the mode.

**Health items.** Codes only; copy is `cod_form.setup.health_<code>` (H.8). Sorted critical → warning → info.

| Code | Severity | When | `count` | `action_url` |
| --- | --- | --- | --- | --- |
| `embed_off` | critical (warning while mode is `legacy`) | new embed is off | – | theme editor deep link |
| `legacy_embed_on` | warning | old embed on **and** (`enable_pre_order_otp` or `partial_payment_enabled`) | – | theme editor |
| `no_shipping_rate` | critical (warning while `legacy`) | no active rate | – | `/features/cod-form/shipping` |
| `no_country` | warning | `general.countries` is empty | – | `/features/cod-form` |
| `cap_reached` | critical (`fallback`) / warning (`grace`) | cap state | cap | `/subscription` |
| `cap_flagged` | info | cap state `flagged` | cap | `/subscription` |
| `otp_unavailable` | warning | `cf_otp_bypassed` events in the last 24 h > 0 | that number | `/features/otp/pre-order` |
| `rule_cod_fee_ignored` | info | enabled COD-type partial rule with amount > 0, partial payments on, `cod_fee_enabled` false | – | `/features/cod-fees` |
| `zip_allow_list_no_exact` | critical | allow list has entries, none exact, and "COD only through the form" is off | – | `/features/limit-cod` |

When the theme cannot be read, `embed.enabled` / `legacy_enabled` are `null` and no embed item is emitted.

**CSV import.** Header required (`name`, `price` mandatory), comma or semicolon, BOM tolerated, 1 MB / 2 000 rows. `province` takes `BU` or `HU-BU`, several separated by `|`. Amounts are decimals in the shop currency. `append` imports the valid rows and reports the rest. `replace` deletes **all** existing rates of the shop and is applied only when the file has no row error; otherwise nothing changes and `created` is 0.

**Payment function (PRE-3).** `PaymentCustomizationService#call` does what it did, then — only when "COD only through the form" is on **and** the form is live — reads the function configuration back and writes it again with `hideCodAtCheckout: true`. For every other shop the configuration is unchanged (key absent). `MetafieldSyncService` re-runs the service when the effective value flips. Turning the form off therefore removes the key.

**Audit.** No buyer data is written: block lists record counts, tokens and API keys record `[changed]`.

## Deviations from ARCHITECTURE.md

1. **Extra file `app/controllers/cod_form_admin/validators.rb`** (`CodFormAdmin::Validators`), inside an owned directory. The engines have no normaliser for `general`, `fraud`, shipping rates, offers, A/B tests, pixels or block entries; these pure validators fill that gap. Form and button configs still go through `Engine::FormConfig` / `Engine::ButtonConfig`.
2. **`PUT forms/:id` returns `publish_errors` next to `warnings`** and stores the normalised draft even when the engine reports errors (a draft may be incomplete). Only structural problems are refused with 422: unknown block type, unknown field key or type, duplicate ids, more than 40 blocks / 60 fields, oversized texts.
3. **A new or duplicated form is created already published** (default config, `published_version: 1`). `Engine::FormTargeting` does not look at the published state, so an unpublished targeted form would serve an empty config. A new form goes live as soon as it has targeting.
4. **`DELETE offers/:id` archives** instead of deleting (sessions and A/B tests refer to offers). Offers that are variants of a running test cannot be edited or archived (422).
5. **Extra response keys** (additive): `embed.legacy_theme_editor_url`, `embed.checked_at`; `status`, `position`, `has_unpublished_changes` on `GET forms/:id`; `warnings` on offers; `invalid`, `over_limit` on block-entry create; `available` on integrations; `sheet_names` on `sheets`.
6. **One extra key in `setup_state`**: `hide_cod_at_checkout` (last value pushed to the payment function). It is not returned by the API.
7. **`CodForm::MetafieldSyncJob#perform(shop_id, run_now = false, force = false)`** — two optional arguments more than K.9; `perform_async(shop_id)` works as specified.
8. **Default form texts.** The default form is `Engine::Defaults.form_config` (via WS1's `Form.default_for`); `config/cod_form/default_texts.json` is served by `GET forms/defaults` and is not copied into the form, because `texts` holds merchant overrides only (C.2). The file is loaded lazily and re-read when it changes; without it a built-in English set is returned.
9. **`payment_customization_service.rb`**: the key is added by a read-merge-write after the existing write, because the configuration itself is built in `payment_function_metafield_service.rb`, which no stream owns. A one-line alternative there (`hideCodAtCheckout: CodForm::MetafieldSyncService.hide_cod_at_checkout?(@shop)`) would save two API calls; then `add_cod_form_hide_cod_key` can be removed.

## Open issues

- **Routes are not merged yet** (`config/routes.rb` had no `cod_form_admin` line when this was written). `forms/defaults` must stay above `resources :forms`.
- **`config/initializers/cod_form.rb` (WS3) did not exist yet.** Its `Setting` hook only needs `CodForm::MetafieldSyncJob.perform_async(shop_id)`; no version bump is required.
- **Unverified GraphQL (F35):** `shop { primaryDomain { host } domains { host } }` in `DomainSyncService` and `paymentCustomization(id:) { metafield(namespace:, key:) { value } }` in `PaymentCustomizationService`. Both are rescued: on a schema error the origin list stays as it is / the key is not added.
- **Session-token callbacks on the public OAuth callback.** `GoogleOauthController#callback` skips `set_shop`, the base callbacks and, by name with `raise: false`, the `ShopifyApp::Authenticated` callbacks (`login_again_if_different_user_or_shop`, `activate_shopify_session`, …). The gem source is not in this mirror; check on a real environment that the callback is reachable without a session.
- **`no_country`**: `countries: []` means "every country" on the storefront, so this item cannot mean "nothing enabled". It is a warning that no country was chosen. Product should confirm the copy.
- **`test_order` checklist step** is done when `setup_state.test_order_at` is set or a test session with an order exists. Nothing writes `test_order_at` yet (WS3's order service could).
- **A/B results** are computed from raw `form_funnel_events` (`metadata.ab`), so they cover at most the 90-day retention.
- **Google account email** is not stored (the two scopes of I.5 do not include it).
- `GET forms/defaults` → `countries` lists the 24 countries of `config/cod_form/countries.json` with English names.

## For WS7

- 402 only fires when the request switches a gated thing on; show the upgrade card from `error.feature` / `error.min_tier`.
- Validation messages are English sentences from this API, except form and button errors, which are engine **codes** (`invalid_color`, `invalid_url`, `required`, …) keyed by engine path — map them to copy.
- `PUT setup`, `PUT fraud`, `PUT shipping_rates/:id`, `PUT offers/:id`, `PUT pixels/:id` accept partial bodies; sending the whole object is fine. An explicit `null` clears a nullable value.
- `preview_url` can be `null`: call `POST setup/test_order` first.
- `embed.enabled === null` means "could not read the theme" — show a neutral state with a refresh button, not "off".
- Preview frame: wait for `{type: "codkf:preview_ready"}` from the iframe before the first post (a payload sent earlier is kept and rendered once the bundle loads). `{type: "codkf:preview_error", reason: "no_asset_base" | "bundle" | "render"}` → show the static placeholder. Pass `?asset_base=` from `bootstrap.preview.asset_base`.
- Google popup: the callback page posts `{type: "codkf:google_sheets", ok: true|false}` to `window.opener` and closes itself on success.
- `analytics/export` is an authenticated download: fetch it with the `api.js` instance as a blob; a plain link has no session token.
- `import_csv` in `replace` mode with any row error changes nothing (`created: 0`): show the errors and ask the merchant to fix the file.
- `POST forms` always needs `multiple_forms` (the default form already exists); ids in targeting may be sent as numbers, numeric strings or `gid://…` and come back as numeric strings.
- Pixel `access_token`: send it only when the merchant typed a new one; omit the key to keep the stored token, send `""` to clear it.
