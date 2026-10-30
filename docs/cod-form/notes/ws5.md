# WS5 — Preact form, chunks, texts, harness

Package: `payment-customization-js/storefront/cod-form/`. Everything below is inside the WS5 paths of ARCHITECTURE.md K.5.

## Files

| Path | Content |
| --- | --- |
| `src/core/index.js` | `open(ctx)`, `preload(opts)`, `preview(payload)`, `close()`; mount (shadow root), session call, boot |
| `src/core/app.jsx` | shell: overlay / sheet / modal / inline, focus trap, Escape, step router, exit confirmation |
| `src/core/store.js`, `reducer.js`, `actions.js` | store and state model of G.6 |
| `src/core/flow.js` | submit flow, order creation (idempotent), hand-off, close/downsell, geo, pixels, thank-you |
| `src/core/api.js` | `text/plain` JSON POST, retry policy, one silent token refresh, `reportError` |
| `src/core/quote.js` | debounced, cancellable, latest-wins quote loop with `seq` |
| `src/core/validate.js`, `phone.js` | twins of `Engine::FormValidator` and `Engine::Phone` (ported line by line) |
| `src/core/i18n.js`, `tmpl.js` | `t(key, vars)`, locale chunk loading, override merge, `{var}` templating |
| `src/core/kit.js`, `rt.js`, `ui.jsx` | the kit handed to lazy chunks, runtime holder, `Lazy`, icons |
| `src/core/blocks/*`, `steps/*` | OrderSummary, Fields, Field, Shipping, Totals, Submit, Blocked; FormStep, Processing, ThankYou |
| `src/core/styles/core.css` | all form CSS (`codkf-` classes, design tokens as custom properties) |
| `src/chunks/*` | `otp`, `payment-option`, `handoff`, `qty-offer`, `bumps`, `downsell`, `upsell`, `discount`, `custom-fields`, `content-blocks`, `india`, `autocomplete`, `threshold`, `embedded`, `pixels-meta/tiktok/google/snap/pinterest`, `preview` |
| `src/i18n/{en,hi,ar,fr,es,hu,sr,ur}.json` | 119 keys each |
| `scripts/export-texts.mjs` | writes `cod-confirm/config/cod_form/default_texts.json` (run; committed output) |
| `scripts/build-ws5.mjs` | private build of the WS5 entries with the options of `snippets/ws5-entries.md` |
| `test/core/*.test.mjs`, `test/fixtures/*` | unit tests; fixtures copied from WS2 (`phone_cases`, `validation_cases`, `countries`) |
| `harness/mock-server.mjs` | node:http mock: pages, `/assets`, Shopify Ajax cart, `/checkout`, Storefront GraphQL, every `/api/form/*` endpoint of section D |
| `harness/fixtures/*` | session, quote catalog, offers, order, geo (HU, IN, RS, CO), schemas, metafield, scenarios |
| `harness/pages/*` | product, cart, home (scenario index), page-builder, designer preview frame, `direct.js` (opener that does not need the loader) |
| `harness/e2e/*.spec.mjs` | 48 Playwright tests |
| `harness/screenshots/*.png` | 29 screenshots (mobile, desktop, RTL) |

## Sizes (gzip, bytes)

`node build.mjs` (WS4's build, current options):

| Output | Size | Limit |
| --- | --- | --- |
| `codk-form-core.js` (one file, no shared chunk; Preact, CSS and English texts inside) | 27 286 | 35 840 (target 32 768) |
| `codk-form-otp.js` | 1 795 | 2 048 |
| `codk-form-payment-option.js` | 677 | 1 536 |
| `codk-form-handoff.js` | 1 548 | 2 048 |
| `codk-form-qty-offer.js` | 1 130 | 2 048 |
| `codk-form-bumps.js` | 857 | 2 048 |
| `codk-form-downsell.js` | 516 | 2 048 |
| `codk-form-upsell.js` | 1 006 | 2 048 |
| `codk-form-threshold.js` | 584 | 2 048 |
| `codk-form-discount.js` | 689 | 2 048 |
| `codk-form-custom-fields.js` | 423 | 2 560 |
| `codk-form-content-blocks.js` | 1 372 | 2 560 |
| `codk-form-india.js` | 287 | 2 560 |
| `codk-form-embedded.js` | 598 | 2 560 |
| `codk-form-autocomplete.js` | 779 | 1 536 |
| `codk-form-pixels-meta / tiktok / google / snap / pinterest.js` | 509 / 750 / 583 / 509 / 498 | 1 229 |
| `codk-form-preview.js` | 1 328 | none yet |
| `codk-form-i18n-en / es / fr / sr / hu / ar / ur / hi.js` | 2 853 / 3 049 / 3 085 / 3 083 / 3 249 / 3 511 / 3 549 / 3 576 | 2 560 — **over** |

The locale chunks are over only because of two build options; with `snippets/ws5-entries.md` applied they are 1 784 / 1 976 / 2 013 / 2 013 / 2 170 / 2 255 / 2 291 / 2 376. Until then `node build.mjs` exits 1 on the size check (the files it writes are correct and are what the e2e suite ran against).

## How to run

```
cd payment-customization-js/storefront/cod-form
node --test "test/core/*.test.mjs"                       # 27 unit tests
node build.mjs --outdir /tmp/codform-ws5-out             # or: node scripts/build-ws5.mjs --outdir <dir>
PORT=4321 ASSETS_DIR=/tmp/codform-ws5-out node harness/mock-server.mjs   # http://localhost:4321/ lists the scenarios
PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers ASSETS_DIR=/tmp/codform-ws5-out npx playwright test harness/e2e --workers=3
node scripts/export-texts.mjs
```

Without `ASSETS_DIR` the server reads `extensions/cod-king-otp-extension/assets`. Each Playwright worker starts its own mock server on a free port.

Harness switches (query string of any page): `scenario=a,b` (see `fixtures/scenarios.json`: default, otp, otp_bypass, otp_throttled, phone_first, partial, blocked, blocked_submit, limit, no_rate, cap, kill, bundle, session_fail, tax, upsell, downsell, offers, custom, pixels, india, multi_country, rtl, urdu, slow_order, order_fail, total_changed, expired_token, ty_message, ty_whatsapp, ty_url, no_token, preset_a, embedded, compact), `locale=`, `country=`, `embed=direct|loader`, `fail=<endpoint>:<status|code>[:count]`, `delay=<endpoint>:<ms>`, `codk_recover=<token>`. Fixed data: OTP code `1234`; phone ending `301111111` is blocked; zip `8888` fails a COD postal rule; zip `9999` has no shipping rate; codes `WELCOME10`, `MIN50`, `NOSTACK`. `GET /__mock/state` returns sessions, orders, events and hand-offs for assertions. `API_PROXY=http://localhost:3000` forwards `/api/form/*` to a real Rails server.

## Results

- Unit: 27 / 27. The phone and validation twins pass every case of WS2's `phone_cases.json` (42) and `validation_cases.json` (17).
- E2E (headless Chromium 1194): 48 / 48, run against WS4's build output and, for the locale / happy / OTP / preview tests, against the private build as well. Covered: happy path mobile and desktop; required-field, phone and server-side validation; quantity stepper and quantity offer; shipping selection, bumps, discount codes; no shipping rate; blocked buyer (quote, submit, postal rule) with Pay online; double tap = one request and one order; order failure and retry with the same idempotency key; total changed; slow order (202 + polling); expired token; tax-exclusive shop; fallbacks (cap, kill switch, session failure, bundle cart); OTP wrong code / edit phone / resend / attempts exhausted / bypass / throttled / close at OTP; phone-first; partial rule → payment step → hand-off call sequence and cart contents; prepaid rule; downsell; upsell accept and decline; thank-you URL, message, WhatsApp; Arabic and Urdu RTL, Hungarian, unknown locale; keyboard-only completion, focus trap, Escape, focus restore; label / live-region wiring and shadow isolation; honeypot; custom fields and content blocks (script in rich text is stripped); India (state list, PIN lookup, GST, mobile prefix); several countries with geo datasets on demand; pixels (five platforms, shared ids, Lead in place of Purchase, `cod_order_placed`, no vendor script without consent); cart source; preset A and `registerPayOnlineHandler`; permalink hand-off without a Storefront token; draft restore and contact capture; recovery prefill; embedded mode; designer preview; page-builder hook and `CODKing.openForm`; the real WS4 embed + loader opening the real core.
- Not exercised: `autocomplete.js` against the real Google Places API (needs a merchant key); cross-origin `import()` from Shopify's CDN (the G.11 risk, needs a development store).

## Deviations from ARCHITECTURE.md

1. **Chunks receive a kit instead of importing shared code.** Every chunk's default export is `(kit) => ({ …parts })`; the core calls it once. Chunks import nothing, so the core is a single file with no hashed shared chunk and chunks stay valid if the build ever switches to IIFE (G.11 risk). Locale chunks still default-export the text object, as specified.
2. **Extra chunk `codk-form-preview.js`** (fixture session for `core.preview`) so preview code is not in the core.
3. **One text key beyond the G.7 list: `back`** (button that returns from the blocked step to the form). It is in all eight locales and in `default_texts.json`.
4. **Focus on open goes to the dialog, not the first field**, so that a phone does not open its keyboard over the order summary. Tab reaches the first control next; step changes focus their main control.
5. **Exit confirmation appears once the buyer has typed something**, not after merely tabbing through a field.
6. **`harness/render-embed.mjs` does not exist**: WS4 built the Liquid renderer as `test/loader/render-embed.mjs`; the mock server imports that for `embed=loader` and has its own `embed=direct` opener.
7. **Storefront API is called on the storefront's own origin** (`/api/2025-07/graphql.json`), not on the myshopify domain; same API, no cross-origin request.
8. `core` also exports `close()` (the loader calls it) and accepts `open({source: "embedded", …})`.
9. English texts are compiled into the core through `import "../i18n/en.json?core"`; the suffix keeps esbuild from sharing the module with the `i18n-en` entry.

## Open issues for the integrator

1. Apply `snippets/ws5-entries.md` in `build.mjs` / `size-limits.json` (WS4's files), then `npm run build` passes its size check.
2. **Province with `mode: "auto"`.** `Engine::FormValidator` requires `province` whenever the field has `required: true` (the default form) unless the schema mode is `hidden`. The client hides the field when the geo endpoint returns no provinces. For a country on the `default` schema with no province data the server would answer `validation_failed` on a field the buyer cannot see. Either the session's `country_schema` should carry `mode: "hidden"` when there is no dataset, or the validator should skip it.
3. **Embedded mode has no caller.** `src/loader` never opens the core with `source: "embedded"`. When `cfg.embedded.enabled`, the loader should call `core.open({cfg, base, source: "embedded", read: () => ({variantId, quantity, properties})})`; `harness/pages/direct.js` shows the call.
4. Response shapes the client assumes where section D leaves room: `offers.quantity` and `offers.thresholds[]` as `{id, config}`; `upsell_accept` returning `order.total_cents`; pixel `platform` values `meta`, `tiktok`, `ga4`, `google_ads`, `snapchat`, `pinterest`; an optional `features.respect_consent` (absent = respect consent). Flat shapes for the two offer objects are tolerated.
5. Flex `gap` is used throughout; Safari older than 14.1 renders the form without those gaps (usable, less tidy).
6. Text keys `item_singular`, `item_plural`, `you_save`, `summary_title` (visible), `otp_placeholder` (visible) are shipped for merchants but only partly used by the form itself.
