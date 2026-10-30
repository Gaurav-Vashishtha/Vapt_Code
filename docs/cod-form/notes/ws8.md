# WS8 — tracking, integrations, abandonment, analytics, jobs

3 Oct 2026 · implements ARCHITECTURE.md I (all), J.2 (notices, overage), K.8, and the privacy part of I.6.

## 1. What other streams call

| Name | Signature | Notes |
| --- | --- | --- |
| `CodForm::FunnelLogger.log` | `(shop_id:, session_token:, type:, meta: {}, at: Time.current) → bool` | Never raises. Fills `country, device, source, form_id, product_ids, utm_campaign, ab` from the session row when the caller did not pass them (what the caller passes wins). `cf_button_view` → Redis counter, `cf_client_error` → Sentry. |
| `CodForm::EventIngestService.call` | `(shop:, session:, client_id:, events:, request_meta:) → {accepted:, dropped:}` | Never raises. Max 20 events; unknown and server-only types dropped. |
| `CodForm::PostOrderJob.perform_async` | `(session_id)` | Integer id or `public_id`. |
| `CodForm::Tracking::ServerDispatchJob.perform_async` | `(session_id, moment)` | `moment` = `"initiate_checkout"` or `"purchase"`. Two optional trailing arguments (`only`, `attempt`) are used by its own per-pixel retries. |
| `CodForm::Tracking::PixelResolver.for` | `(shop, product_ids:, collection_ids:) → [pixel hashes]` | **Storefront representation** (C.6): no token, browser pixels only. |
| `CodForm::Tracking::PixelResolver.server_pixels` | same arguments | With `access_token`. Server use only. |
| `CodForm::Tracking::EventMap` | `.event_name`, `.browser_event_name`, `.event_id`, `.moment_enabled?` | The I.2 table. |
| `CodForm::Tracking::TestEvent.call` | `(tracking_pixel_record) → {"ok", "response"}` | Used by `pixels#test`. |
| `CodForm::CapNotifyJob.perform_async` | `(shop_id, period)` | |
| `CodForm::OtpUnavailableNotifyJob.perform_async` | `(shop_id)` | |
| `CodForm::Abandonment::RecoveryService.prefill` | `(shop, recovery_token) → Hash \| nil` | D.1 `prefill` plus `"recovered_from"` (abandoned session's public id). |
| `CodForm::Abandonment::RecoveryService.complete!` | `(shop, session) → Integer` | Called by `PostOrderJob`. |
| `CodForm::Analytics::Query` | `.summary(shop, from:, to:, filters:, compare:)`, `.breakdown(shop, by:, from:, to:)`, `.export_rows(shop, from:, to:, filters:, by:)`, `.export_csv(...)` | String-keyed hashes ready for `render json:`. |
| `CodForm::Integrations::GoogleSheets::Client` | `.new(integration)`, `#refresh!`, `#list_spreadsheets`, `#sheet_names`, `#create_spreadsheet`, `#append_row`, `#empty_sheet?` | |
| `CodForm::Integrations::KlaviyoClient.track` / `OmnisendClient.track` | `(shop, event:, profile:, properties:, …)` | Never raise. |
| `CodForm::Integrations::Rabbitpay.handler_expected?` | `(shop) → bool` | Interface only (PRE-6). |
| `CodForm::PrivacyService` | `.redact_customer(shop, phone:, email:)`, `.export_customer(...)`, `.redact_shop(shop)`, `.handle_webhook(topic:, payload:)` | |

## 2. Files

Created — services
- `app/services/cod_form/tracking/`: `event_map.rb`\*, `event_builder.rb`\*, `payloads.rb`\*, `pixel_resolver.rb` (selection logic pure\*), `http.rb`, `dispatcher.rb`, `test_event.rb`, `meta_client.rb`, `tiktok_client.rb`, `ga4_client.rb`, `google_ads_client.rb`, `snapchat_client.rb`, `pinterest_client.rb`
- `app/services/cod_form/integrations/`: `event_payloads.rb`\*, `registry.rb`, `klaviyo_client.rb`, `omnisend_client.rb`, `marketing_consent.rb`, `rabbitpay.rb`, `google_sheets/client.rb`, `google_sheets/row_builder.rb`\*
- `app/services/cod_form/abandonment/`: `mark_abandoned_service.rb`, `recovery_service.rb`, `recovery_link.rb`\*, `draft_order_service.rb`
- `app/services/cod_form/analytics/`: `event_meta.rb`\*, `rollup.rb`\*, `funnel.rb`\*, `query.rb`, `shop_time.rb`
- `app/services/cod_form/{event_ingest_service,funnel_logger,privacy_service}.rb`

\* pure Ruby (stdlib only), covered by plain minitest.

Created — workers, mailer, tests
- `app/workers/cod_form/{post_order_job,cap_notify_job,otp_unavailable_notify_job,overage_billing_job}.rb`
- `app/workers/cod_form/tracking/server_dispatch_job.rb`, `…/integrations/google_sheets_append_job.rb`, `…/abandonment/sweep_job.rb`, `…/analytics/{rollup_job,purge_job}.rb`
- `app/mailers/cod_form_mailer.rb`, `app/views/cod_form_mailer/{usage_notice,otp_unavailable_notice}.html.erb`
- `test/services/cod_form/analytics/{rollup,funnel,event_meta}_test.rb`, `…/analytics/all.rb`, `test/services/cod_form/tracking/{event_map,payloads,pixel_resolver}_test.rb`, `test/services/cod_form/integrations/{row_builder,event_payloads}_test.rb`, `test/services/cod_form/abandonment/recovery_link_test.rb`

Edited
- `app/models/form_funnel_event.rb` — `COD_FORM_EVENT_TYPES`, `ALL_EVENT_TYPES`, validation on the union, scope `cod_form` (see deviation 1)
- `app/models/abandoned_cart.rb` — `WEBHOOK_SOURCES = %w[shopflo custom cod_form]`
- `app/services/campaign_attribution_helper.rb` — `ALLOWED_KEYS` gains `ttclid sccid epik`
- `app/controllers/script_controller.rb` — `delete_data` calls the guarded `cod_form_privacy_webhook`
- `config/schedule.yml` — four own entries + WS3's `cod_form_session_purge_job` (snippet merged)
- `config/locales/en.yml` — `en.cod_form_mailer.*`

Files beyond the K.8 list (all inside WS8 folders): `event_builder`, `payloads`, `http`, `dispatcher`, `test_event`, `event_payloads`, `registry`, `marketing_consent`, `rabbitpay`, `recovery_link`, `draft_order_service`, `event_meta`, `shop_time`, and the test folders `integrations/` and `abandonment/`.

## 3. Server pixels

| Platform | Endpoint | Auth | Dedup id field | PII |
| --- | --- | --- | --- | --- |
| Meta | `POST https://graph.facebook.com/v19.0/<pixel_id>/events` | `access_token` query | `event_id` | SHA-256: `em ph fn ln ct zp country external_id` |
| TikTok | `POST https://business-api.tiktok.com/open_api/v1.3/event/track/` | header `Access-Token` | `event_id` | SHA-256 email, phone (E.164 with `+`), external_id |
| GA4 | `POST https://www.google-analytics.com/mp/collect?measurement_id=&api_secret=` | `api_secret` query | `transaction_id` | none sent |
| Google Ads | existing `NetworkServices::GoogleConversionService.call_purchase(order, setting, gclid:)` | Setting token | `orderId` | none |
| Snapchat | `POST https://tr.snapchat.com/v3/<pixel_id>/events?access_token=` | query | top-level `event_id` (pairs with `client_dedup_id`) | SHA-256 |
| Pinterest | `POST https://api.pinterest.com/v5/ad_accounts/<ad_account_id>/events` | Bearer | `event_id` | SHA-256 |

- Per pixel: `access_token` on the `tracking_pixels` row; Pinterest also needs `config.ad_account_id`; optional `config.test_event_code` (Meta, TikTok; on GA4 it sets `debug_mode`).
- Timeouts 3 s connect / 8 s read. A retryable failure (network, 408, 429, 5xx) re-enqueues **that pixel only** after 30 s, 5 min, 30 min. Other failures are a warn line; from the 6th failure per shop per hour one Slack alert.
- URLs, headers, bodies and vendor response bodies are never logged.
- Consent: with `general.consent.respect_customer_privacy` (default), marketing pixels need `tracking.consent.marketing`, GA4 needs `analytics`.
- The implicit Meta pixel from `Setting` sends its **purchase** through the existing `MetaConversionService.call_purchase`, so the id stays `order_<id>_purchase`. Its form-open event goes through `MetaClient`.
- Google Ads server conversion exists only for `Setting#google_conversion_id`; `tracking_pixels` rows of platform `google_ads` are browser-only. `gclid:` only is passed (the I.3 fix).
- Test sessions send nothing.

## 4. Integrations

| Integration | Credentials / config | ENV |
| --- | --- | --- |
| Google Sheets | `cod_form_integrations` `google_sheets`: `credentials {refresh_token, access_token, expires_at}`, `config {spreadsheet_id, sheet_name, columns}` | `GOOGLE_SHEETS_CLIENT_ID`, `GOOGLE_SHEETS_CLIENT_SECRET` |
| Klaviyo | `credentials {private_api_key}`, `config {events: {order, abandoned}}` | optional `KLAVIYO_API_REVISION` (default `2026-07-15`) |
| Omnisend | `credentials {api_key}`, same config | – |
| RabbitPay | `config {enabled}` | – (interface only) |
| Google Ads server upload | existing `Setting` columns | existing `GOOGLE_ADS_DEVELOPER_TOKEN` |
| Privacy webhook | – | existing `SHOPIFY_API_SECRET` |
| Revenue conversion | – | existing `OPEN_EXCHANGE_RATES_APP_ID` |

- Sheets rows are written with `USER_ENTERED`; `RowBuilder.cell` prefixes text starting with `= + - @` with an apostrophe, so buyer text cannot run as a formula and `+36…` phone numbers stay text.
- A header row is written when the first cell of the sheet is empty.
- `GoogleSheetsAppendJob`: retry 8; only transient errors are retried. A revoked account or a missing sheet sets the integration to `error` with a merchant-readable `last_error`.
- Events: `COD Form Order Placed`, `COD Form Abandoned` (carries `recovery_url`). Gate `klaviyo_omnisend`.
- Google address autocomplete (INT-3) needs no server code: the chunk calls Google with the merchant's key.

## 5. Funnel, rollups, analytics

- Stored event types: the 22 `cf_*` types other than `cf_button_view` and `cf_client_error`.
- Button views: `HINCRBY codf:bv:<shop_id>:<yyyy-mm-dd> "<country>|<device>|<product_id>" 1`, date in the **shop's** time zone, TTL 3 days, at most 5 000 fields per shop per day.
- `codf:active:<utc date>` (Redis set, TTL 3 days) lists shops with funnel activity; the rollup reads it.
- Funnel steps `form_opens, first_inputs, shipping_selected, submit_attempts` count **sessions**; every other metric counts events.
- Test sessions (`metadata.test == true`) are excluded from every aggregate.
- Rollup keeps at most 500 values per dimension per shop per day (largest first).
- `Query.summary` returns the D.15 keys plus `otp`, `offers`, `recovery`; `previous` is null unless `compare` is set, and then also carries `range`, `form_opens`, `change`.
- Rates are percentages 0–100 with two decimals.
- Two or three filters together are answered from raw events, limited to 90 days (`"limited_to_days": 90`); button views are then available for the last 3 days only.
- `breakdown` takes no extra filters (single-dimension rollups, B.17). For `by=offer` rows also carry `views`, `accepts`, `accept_rate`.

## 6. Abandonment

- Eligible shop: COD Form mode, `general.abandonment.enabled`, gate `abandonment_recovery`, and abandoned-cart messages on.
- Anchor `source_payload` = `{session, items, totals}` **plus** a `checkout` envelope, because `Whatsapp::ScheduleAbandonedCartRemindersJob` skips anchors without `payload['checkout']`.
- A session with an email but no phone is marked abandoned and sent to Klaviyo / Omnisend; it gets no anchor (messages need a phone).
- The recovery link uses `tracking.page_url` only when it is https on the shop's own hosts; otherwise the home page.
- `RecoveryService.complete!` also recovers abandoned sessions of the same phone or email (last 30 days), not only the one named in `tracking.recovered_from`.

## 7. Cron (`config/schedule.yml`)

| Key | Cron (UTC) | Class | Queue |
| --- | --- | --- | --- |
| `cod_form_analytics_rollup_job` | `7 * * * *` | `CodForm::Analytics::RollupJob` | low |
| `cod_form_analytics_purge_job` | `41 3 * * *` | `CodForm::Analytics::PurgeJob` | low |
| `cod_form_abandonment_sweep_job` | `*/5 * * * *` | `CodForm::Abandonment::SweepJob` | low |
| `cod_form_overage_billing_job` | `30 2 * * *` | `CodForm::OverageBillingJob` | administration |
| `cod_form_session_purge_job` (WS3) | `40 3 * * *` | `CodForm::SessionPurgeJob` | low |

Backfill one day: `CodForm::Analytics::RollupJob.perform_async(shop_id, "2026-10-01")`.

## 8. Verification

- `ruby -wc` on all 57 WS8 Ruby files (new and edited): no errors, no warnings. ERB views compile; `en.yml` and `schedule.yml` parse.
- `ruby test/services/cod_form/analytics/all.rb` → **106 runs, 514 assertions, 0 failures, 0 errors** (plain minitest, no Rails).
- Not committed: 41 further checks were run against hand-written stand-ins for Rails, ActiveRecord, Redis and HTTP (event ingest, dispatcher and per-pixel retry, analytics query shape, cap notices, OTP notice, overage billing, Klaviyo / Omnisend / Sheets clients and append job, abandonment). All passed. They prove the control flow, not the SQL.
- Not run here (no database, the app cannot boot): every ActiveRecord query, the mailer, the GraphQL calls, real vendor HTTP.

## 9. Deviations from ARCHITECTURE.md

1. **`FormFunnelEvent::EVENT_TYPES` stays Express-only.** B.19 says it "gains the `cf_*` list". The public, unauthenticated `POST /form_funnel/ingest` whitelists by that constant, so adding the list would let anyone write `cf_order_created` (with a revenue value) for any shop. The `cf_*` list is `COD_FORM_EVENT_TYPES`; the model validates against `ALL_EVENT_TYPES`. Nothing else in the tree reads `EVENT_TYPES`.
2. **`PixelResolver.for` returns the storefront representation**; `server_pixels` returns the token-carrying one.
3. **Anchor `source_payload` has an extra `checkout` key** (section 6).
4. **Abandonment eligibility also accepts a BSP `abandoned_cart` binding**, not only the two `Setting` flags; otherwise BSP-only shops would never get an anchor.
5. **Two extra rollup metric keys**: `otp_bypassed`, `prepaid_orders` (additive to B.17).
6. **`Query.summary` returns extra keys** (section 5).
7. **`ServerDispatchJob#perform` has two optional trailing arguments** for per-pixel retries.
8. **Privacy webhook acts only on a valid Shopify HMAC** and needs the `X-Shopify-Topic` header. An unsigned call still answers `{ok: true}` and changes nothing.
9. **`redact_customer` also deletes** the buyer's funnel events and abandoned-form rows, and blanks `tracking`, `attribution`, `client_id`, `user_agent`, `recovery_token`, `quote_snapshot.order_response`.
10. **Pinterest server event for form open is `add_to_cart`** (API spelling); the browser name stays `addtocart` (`EventMap.browser_event_name`).
11. **Sibling `require_relative` lines are guarded with `unless defined?(::Rails)`**, as WS2 asked.

## 10. Open issues

1. **Lead event id.** A pixel with `purchase_event: "lead"` is sent server-side as `order_<id>_lead` (I.2). The order response gives the browser only `purchase_event_id`. The browser chunks must derive `order_<id>_lead` for such pixels, or lead events will not deduplicate.
2. **Partial orders and overage.** `OrderWebhookHook#finish_handoff` counts a partial order but does not enqueue `PostOrderJob`, so partial orders beyond the cap are not added to `over_cap_count` and get no Sheets row or CRM event. Inert today (no rate). Fix: enqueue `PostOrderJob` there.
3. **Sheets `note` column is empty.** The order note (`fields.note`) is not stored on the session. It fills once the submit stores it in `custom_fields["note"]`.
4. **Sheets credentials have no `email`** (B.18 lists it); the OAuth callback does not store one. Nothing reads it.
5. **Indexes.** `PurgeJob` filters `form_funnel_events` by `event_type` + `occurred_at` across shops; the only matching index starts with `shop_id`. Expect a scan once a day. An index on `(event_type, occurred_at)` would fix it (needs a migration on an existing table, so not done).
6. **The existing `MetaConversionService` logs its full payload** (hashed email and phone, raw IP and user agent). The implicit Setting pixel's purchase goes through it by design; the new clients log nothing.
7. **GraphQL not validated here** (F35): `draftOrderCreate` (abandoned-form draft), `customerSmsMarketingConsentUpdate`, `customerEmailMarketingConsentUpdate`, `order { customer }`.
8. **Vendor endpoints were written from documentation, not called.** Check each with the pixel test button on a real account, Pinterest and Snapchat first.
9. **Buyer who abandons the form and then orders through Shopify checkout** is recovered only by the existing rules (`AbandonedCartStatusUpdateJob` matches by checkout id; the WhatsApp TTL check matches by phone).
10. **The admin link in the two emails** is `https://<shop>/admin/apps` (the app handle is not in the code base).
