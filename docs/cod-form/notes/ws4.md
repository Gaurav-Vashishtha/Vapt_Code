# WS4 notes — embed, loader, button, extras, widget, build

3 Oct 2026 · storefront package `payment-customization-js/storefront/cod-form/`

## 1. Result

| Budget (gzip, `size-limits.json`) | Limit | Achieved |
| --- | --- | --- |
| inline: CSS + `window.__CODKF__` + slot script, default config, product page | 1 843 | **1 776** |
| `codk-form-loader.js` | 3 277 | **3 255** (6 909 raw) |
| `codk-form-extras.js` | 1 536 | **1 532** (3 225 raw) |
| `codk-form-qty-widget.js` | 3 072 | **2 466** (5 101 raw) |
| `default_path` = inline + loader (product decision 14: 5 KB) | 5 120 | **5 031** |
| `with_extras` = inline (preset C: sticky + drawer + rename) + loader + extras (6.5 KB) | 6 656 | **6 573** |

Numbers are `zlib.gzipSync(level 9)` as printed by `npm run size` (the `gzip` CLI adds about 20 bytes
of file-name header). The embed prints **0 bytes** when the metafield is absent or disabled, the
country is not enabled, or the page type is off.

Checks run here:

- `npm test`: 40 loader / shared / widget / Liquid tests pass (`node --test "test/loader/*.test.mjs"`);
  with WS5's `test/core` the whole run is green.
- `npm run e2e:loader`: 71 checks pass in headless Chromium (Playwright 1.56, chromium-1194).
- Smoke test against WS5's real core through `harness/mock-server.mjs`: real embed → real loader →
  real form opens from the COD button, no console errors.
- `npm run build`: every WS4 output and both composite limits pass. **The command still exits 1**
  because WS5's eight `codk-form-i18n-*.js` files are 2 853–3 576 B against the 2 560 B budget of
  G.10, and `codk-form-preview.js` (not in G.10) has no budget (warning only). See section 6.

## 2. Files

Extensions repo (`payment-customization-js`):

- `extensions/cod-king-otp-extension/blocks/cod-form-embed.liquid` (new, 13.0 KB of Liquid)
- `storefront/cod-form/package.json`, `build.mjs`, `size-limits.json`, `README.md`, `.gitignore`
- `storefront/cod-form/src/shared/` — `selectors.js money.js dom.js storage.js events.js attribution.js consent.js cart.js fallback.js`
- `storefront/cod-form/src/loader/` — `index.js config.js product.js button.js visibility.js open.js public-api.js recover.js`
- `storefront/cod-form/src/extras/` — `index.js sticky.js cart-buttons.js theme-buttons.js extras.css`
- `storefront/cod-form/src/widget/` — `index.js tiers.js widget.css`
- `storefront/cod-form/test/loader/` — `shared.test.mjs loader.test.mjs widget.test.mjs selectors.test.mjs embed.test.mjs`,
  `render-embed.mjs` (LiquidJS render of the real block; also used by the build and by WS5's mock server),
  `harness-server.mjs`, `browser.e2e.mjs`, `helpers/dom-stub.mjs`, `fixtures/{metafield.json,product.html,cart.html,home.html,core-stub.js}`
- generated: `extensions/cod-king-otp-extension/assets/codk-form-*.js` (built at the end of this work, with WS5's sources as they were then)

Backend repo (`cod-confirm`): `docs/cod-form/PAGE_BUILDERS.md`, `docs/cod-form/snippets/ws4-app-embed.liquid.md`,
`docs/cod-form/snippets/ws4-payment-function.md`, this file.

No locales snippet: the block schema has no settings, and its name is a literal, so
`locales/en.default.json` needs nothing.

## 3. Build and test

```
cd payment-customization-js/storefront/cod-form
npm install
npm run build        # all outputs → ../../extensions/cod-king-otp-extension/assets, then size check
npm run size         # size check only
npm test             # node --test, no browser
npm run e2e:loader   # headless Chromium on the loader fixtures (stub core)
```

Details, flags and the internal APIs are in the package `README.md`.

## 4. Theme assumptions

1. The product form is `form[action*="/cart/add"]` containing `[name="add"]`; the main form is the
   first one whose `[name="id"]` holds a variant of the page's product, else the first with an Add button.
2. Buy buttons anchor = closest common container of `[name="add"]` and `.shopify-payment-button` in
   that form (Dawn: `.product-form__buttons`); with no payment button the anchor is the Add button.
   If the common container is the form itself, the anchor is the payment button (below) or the Add button (above).
3. Variant changes are visible through one of: a `change` / `input` event, the `value` attribute of
   `[name="id"]`, `history.replaceState`, or a DOM re-render. All four trigger a re-read; after a
   re-render that removes the slot, the slot and the button are created again.
4. Quantity is `[name="quantity"]` inside the form or linked with the `form` attribute.
5. Unbranded Buy now: a `BUY_NOW` match that is not inside `[class*="--branded"]`,
   `[data-shopify-buttoncontainer]`, `shopify-accelerated-checkout` or the More payment options link.
   **A button with a `--unbranded` class counts as unbranded even inside `<shopify-accelerated-checkout>`**
   (current Shopify markup puts the theme-styled Buy it now there). To verify on a development store.
6. Cart buttons go before the **first** match of `CART_CHECKOUT` (cart page) / `CART_DRAWER` (elsewhere),
   or of the merchant's selector. Themes whose first match is a hidden duplicate need a custom selector.
7. Cart changes are detected by a `PerformanceObserver` on requests to `/cart/add|change|update|clear`
   (then `/cart.js` is read once for `{total}` and the total range).
8. Money: `shop.money_format` with HTML stripped; `{total}` uses Shopify's format keys.
9. Tested here on Dawn-like fixtures only. NFR-9 (ten most-used themes, GemPages, PageFly, Zipify) needs real stores.

## 5. Deviations from ARCHITECTURE.md (each one for size or safety)

| # | Document | Built | Why |
| --- | --- | --- | --- |
| 1 | The loader injects `codk-form-extras.js` (G.3) | The Liquid prints a second deferred `<script>` for it, only when an extra is on for the page; the loader does not inject it | Saves about 90 B in the loader; same condition, same load order. In test-only mode a non-preview visitor still downloads the file (it does nothing). |
| 2 | Hide toggles are "pure CSS, no JS" (G.2) | Add to cart / Buy now rules are scoped to `html.codkf-ok`, wallets to `html.codkf-on`, Checkout to `.codkf-cart:not([hidden]) ~ …` | Theme buttons are hidden only while a working COD button is there: never a dead end when the variant is ineligible, the script is blocked, or no cart anchor was found. Preset A ignores "hide Buy now". |
| 3 | Icons are inline SVG in the loader (C.1.2) | The Liquid emits the chosen icon as a CSS mask on `.codkf-btn:before` | About 250 B less in the loader; no icon bytes when the icon is `none`. |
| 4 | Sticky / cart button CSS in the inline `<style>` (G.2) | Injected by `codk-form-extras.js` | Extras-only bytes stay out of the default path (product decision 14). |
| 5 | `CART_CHECKOUT` used by `cart-buttons.js` (G.3 step 5) | On the cart page the Liquid puts that list in `btn.cart.selector`; extras carries only compact `BUY_NOW` / `CART_DRAWER` lists (same matches, redundant entries removed — `SUBSUMED_BY`, `DEAD` in `selectors.js`, both test-checked) | The three verbatim lists alone are 600 B gz; extras could not fit 1.5 KB otherwise. |
| 6 | Test-only: continue only with `?codk_preview=` in the URL (G.3 step 2) | Also when the tab's `sessionStorage.codkf_preview` holds a token | Preview survives product → cart navigation. |
| 7 | Page gate: product page → `pages.product` (G.2) | A product page that is off or fails a product gate is treated as `page: "other"`: no product button, but drawer / quick-buy / hooks still work when `pages.drawer` is on | The cart drawer exists on product pages too. With `pages.drawer` and `pages.quick_buy` off it prints nothing, as documented. |
| 8 | `vis` / `rules` min–max always emitted | Emitted as `null` when the buyer's currency ≠ shop currency | The bounds are in shop currency; the server still enforces them. |
| 9 | `window.CODKing.on(name, handler)` | `name` is the full event name (`"codking:form:open"`); the handler gets the `CustomEvent` | No translation layer in the loader. |
| 10 | `build.mjs` imports `harness/render-embed.mjs` (K.4) | It imports `test/loader/render-embed.mjs` (LiquidJS render of the real block); WS5's mock server uses the same file | The budget measures the shipped Liquid, not a port of it. `liquidjs` is a devDependency only. |
| 11 | Observer of step 5 "disconnects after 10 s with no match unless `pages.drawer`" | One observer for all extras tasks, never disconnected | 60 B; `pages.drawer` is on by default so it rarely applied. Runs at most once per frame. |
| 12 | Intent event `pointerenter` | `mouseover` (+ `touchstart`, `focusin`) on `document` | Bubbling equivalent for a delegated listener. |
| 13 | `ctx` keys "exactly" | One extra key, `sellingPlan`, used only by `goToCheckout` | Subscriptions go to Shopify checkout with the selling plan. |
| 14 | `with_extras` scenario | Preset C with rename, sticky and drawer (the wording of product decision 14) | With every option on (subtitle, animation, shadow, all hide toggles, prepaid label, quick-buy) the inline part is 2 064 B and the total 6 851 B; the build prints it as information. |

Also: `drawer.label` and `sticky.label` are resolved in Liquid (`btn.drawer.label` is one key more than the G.2 example).

## 6. Open issues for the integrator

1. **Liquid size cap.** Shopify limits a theme app extension to 100 KB of Liquid. `app-embed.liquid`
   is 84 456 B; with the new block the extension is at **98 276 B**. The new block was minified to
   13 KB for this reason (a test fails above 100 000). If the owner's uncommitted work on
   `app-embed.liquid` adds more than about 1.7 KB, `shopify app deploy` will refuse the extension.
   Verify the exact limit on deploy; the durable fix is to move inline script out of the old block.
2. **`npm run build` exits 1** on WS5's i18n chunks (section 1). Decide: trim the texts, or raise
   `"codk-form-i18n-*.js"` in `size-limits.json` (and G.10), and add a budget for `codk-form-preview.js`.
3. **Cross-origin `import()`** of `codk-form-core.js` / the widget from Shopify's CDN (risk already
   listed in G.11): to verify on a development store. The loader itself and extras are classic scripts.
4. **`asset_url` with a query string.** `base` is derived after stripping `?…`; confirm the chunk URLs
   resolve on a real store (versioned path, no signed query needed).
5. **Unbranded Buy now inside `<shopify-accelerated-checkout>`** (assumption 5): confirm rename and
   preset A on a live theme; before hydration Shopify shows a skeleton that may briefly take the renamed text.
6. **`_codkDiscounts` for the quantity widget (OFF-4).** Written as `<variantId>:<line discount in
   currency units, 2 decimals>|<tier label>` when the buyer clicks Add to cart / Buy now, merged with
   existing entries. The discount function applies it as a fixed amount on the line whatever the final
   quantity is, and Shopify's dynamic Buy it now may not carry cart attributes. Accepted trust model
   (PM Q11); form orders are not affected.
7. **Legacy embed.** With "COD King OTP Block" still on and Express features enabled, its capture-phase
   click handler competes with preset A and takes the theme's Checkout button. The guard is delivered as
   `snippets/ws4-app-embed.liquid.md`; not applied.
8. **PRE-3 and postal prefixes at checkout**: `snippets/ws4-payment-function.md`; not applied.
9. `CODKing.close()` calls `core.close()` (WS5 exports it).
10. Builder menu names and example class names in `PAGE_BUILDERS.md` are from documentation knowledge,
    not from live GemPages / PageFly / Zipify stores; check them before publishing the page.
11. Headroom is thin: loader 22 B, extras 4 B, inline 67 B. Any addition needs a matching cut.

## 7. Integrator checklist

1. `cd payment-customization-js/storefront/cod-form && npm install && npm run build` → commit
   `extensions/cod-king-otp-extension/assets/codk-form-*.js` (after resolving issue 2).
2. Commit `blocks/cod-form-embed.liquid`. Do not add `"javascript"` / `"stylesheet"` to its schema.
3. `npm test` and `npm run e2e:loader`.
4. On a development store: enable the embed "COD King – COD Form", then check issues 1, 3, 4, 5.
5. Keep `snippets/ws4-*.md` for the embed owner's and the function owner's next releases.
