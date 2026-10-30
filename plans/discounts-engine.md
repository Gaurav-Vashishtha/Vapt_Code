# Plan: In-App Discounts Engine (cod-confirm / COD King)

**Status:** In progress on branch `feature/discounts-engine`. ✅ Phases 1–7 done & build-verified (data model, service layer, job, admin API, admin React UI, widget payload, notifik-svelte coupon UI/apply). Coupon-side `discount`-field clobber resolved via merge-safe `couponCart.js`; partial-payment *rule* apply still replaces the field (noted below). ⏳ Remaining: 8 (uninstall cleanup), 9 (QA + live Shopify mutation round-trip).
**Target app:** `cod-confirm` (Rails 7.2 + React/Polaris embedded admin + storefront widget).
**Goal:** A new **Discounts** feature screen where a merchant builds a discount in-app (mirroring Shopify's own builder), and on save we create/update a **real native Shopify discount** via GraphQL and mirror it in our DB. Eligible discounts surface as coupons on the storefront widget and are applied to the cart via `/cart/update.js`.

> **Hard constraint (from product decision):** No Shopify Functions / no discount-function interference. We use Shopify's **native** discount types only. This means the existing `DiscountAutomaticAppCreateService` (which requires a deployed Function) is **NOT** used for this feature.

---

## 1. Scope

### In scope (v1)
- Discount **method**: `code` or `automatic`.
- Discount **type**: `amount_off` (fixed), `percentage`, `buy_x_get_y` (BXGY).
- **Targeting**: all products (default) / specific products / specific collections.
- **Minimum requirement**: none / minimum subtotal / minimum quantity.
- **Combinations**: order / product / shipping (`combinesWith`).
- **Schedule**: starts at / ends at (optional), usage limit, once-per-customer.
- Persist to our `discounts` table + create/update the real Shopify discount.
- Surface eligible discounts as coupons on the widget; apply code discounts via `/cart/update.js`.
- Full lifecycle: create, update, activate/deactivate, delete (including deleting the Shopify-side object — see §9, learned from the cartpe orphan gap).

### Out of scope (v1 — note explicitly in UI)
- Free-shipping discounts (easy follow-up: `discountCodeFreeShippingCreate` / `discountAutomaticFreeShippingCreate`).
- Per-customer-segment targeting (we use "all customers" only).
- Product-discounts-on-same-cart-line tag combinations (Plus-only).
- Importing pre-existing Shopify discounts (this plan is the "create-in-app" path only).

---

## 2. The mutation matrix (native, no Functions)

This is the core mapping the service layer implements. Method (rows) × Type (cols):

| | amount_off / percentage | buy_x_get_y |
|---|---|---|
| **code** | `discountCodeBasicCreate` / `discountCodeBasicUpdate` | `discountCodeBxgyCreate` / `discountCodeBxgyUpdate` |
| **automatic** | `discountAutomaticBasicCreate` / `discountAutomaticBasicUpdate` | `discountAutomaticBxgyCreate` / `discountAutomaticBxgyUpdate` |

- **Delete:** `discountCodeDelete` (code) / `discountAutomaticDelete` (automatic).
- **Activate / deactivate:** `discountCodeBulkActivate` / `discountCodeBulkDeactivate`; `discountAutomaticActivate` / `discountAutomaticDeactivate`. (v1 may instead deactivate by setting `endsAt` in the past via the Update mutation — simpler, one code path. Decide in §11.)
- **Required scope:** `write_discounts` (already granted — see `config/initializers/shopify_app.rb`).
- **API version:** `2025-07` (already pinned).

### Key input shapes (build these from the `Discount` model)

**`DiscountCodeBasicInput` / `DiscountAutomaticBasicInput`** (amount/percentage):
```jsonc
{
  "title": "...",
  "code": "SAVE10",                       // code method only; omit for automatic
  "startsAt": "2026-01-01T00:00:00Z",      // required
  "endsAt": "2026-12-31T23:59:59Z",        // optional
  "customerSelection": { "all": true },    // code method; automatic has no customerSelection
  "customerGets": {
    "value": { "percentage": 0.10 }        // OR { "discountAmount": { "amount": "50.0", "appliesOnEachItem": false } }
                                           // percentage is a 0–1 fraction, NOT 0–100
    ,"items": { "all": true }              // OR products / collections — see targeting below
  },
  "minimumRequirement": {                  // optional
    "subtotal": { "greaterThanOrEqualToSubtotal": "999.0" }
    // OR "quantity": { "greaterThanOrEqualToQuantity": "2" }
  },
  "combinesWith": { "orderDiscounts": true, "productDiscounts": false, "shippingDiscounts": true },
  "usageLimit": 100,                       // code only
  "appliesOncePerCustomer": true           // code only
}
```

**`DiscountCodeBxgyInput` / `DiscountAutomaticBxgyInput`** (BXGY):
```jsonc
{
  "title": "...",
  "code": "B2G1",                          // code method only
  "startsAt": "...",
  "customerBuys": {
    "items": { "collections": { "add": ["gid://shopify/Collection/123"] } }, // or products / all
    "value": { "quantity": "3" }           // OR { "amount": "100.0" } (spend X)
  },
  "customerGets": {
    "items": { "all": true },              // the "get Y" set
    "value": { "discountOnQuantity": { "quantity": "1", "effect": { "percentage": 1.0 } } } // 100% off 1 = free
  },
  "combinesWith": { ... },
  "usesPerOrderLimit": 1,                   // code only
  "appliesOncePerCustomer": true
}
```

**Targeting (`DiscountItems`)** — reused in `items` everywhere:
- All: `{ "all": true }`
- Products: `{ "products": { "productsToAdd": ["gid://shopify/Product/…"], "productVariantsToAdd": [] } }`
- Collections: `{ "collections": { "add": ["gid://shopify/Collection/…"] } }`

**Reference example confirmed in docs:** "10% off all items after spending $50, once per customer" maps exactly to `discountCodeBasicCreate` with `customerGets.value.percentage`, `customerGets.items.all`, and `minimumRequirement.subtotal.greaterThanOrEqualToSubtotal`.

---

## 3. Critical correctness notes (read before building)

1. **`percentage` is a 0–1 fraction.** 10% → `0.10`. The existing `DiscountCreateService#normalize_percentage` already handles "user typed 10 → 0.10"; reuse that normalization.
2. **Automatic discounts have NO code and CANNOT be applied via `/cart/update.js`.** Shopify auto-applies them at cart/checkout. So:
   - `code` discounts → widget shows an "Apply" button → `POST /cart/update.js { discount: "CODE" }`.
   - `automatic` discounts → widget only shows progress / "unlocked automatically" messaging; **no apply call**. Do not try to apply an automatic discount by code — it has none.
   This splits the widget UX into two coupon kinds. Build the model/flag for it explicitly.
3. **Shopify is the source of truth for the actual price reduction.** Our `discounts` table is a mirror/projection for the admin UI and for driving widget eligibility hints. Always read back what Shopify actually allocated after apply (`discountCodes[].applicable`, `discountAllocations`) — never trust our client-side eligibility as authoritative.
4. **Client eligibility is advisory.** Compute cheap gates (min subtotal, date window) in JS for "🔓 unlock at ₹X more" UX. Product/collection scoping is hard client-side (the browser doesn't know collection membership). v1 approach: for product/collection-scoped discounts, **optimistically apply and trust Shopify's read-back** rather than re-deriving eligibility in JS. (Alternative: precompute eligible variant IDs server-side into the payload — defer to v2.)
5. **Combinations matter for COD.** This app already creates a partial-payment automatic discount (`partial_discount_automatic_app_ensure_service.rb`). If a merchant coupon doesn't set `combinesWith` correctly, applying it can silently knock that out. Default new discounts to `combinesWith.orderDiscounts = true` and surface the toggle in the UI.
6. **Do NOT reuse `DiscountCreateService` as-is.** It hard-codes a 2-hour window, a random `CODK-XXXX` code, all-customers, all-items, once-per-customer. It was built for prepaid conversion, not merchant-authored discounts. We build new, generalized service objects (but copy its client-acquisition + `coerce_value`/`normalize_percentage` helpers).

---

## 4. Data model

### Migration: `db/migrate/<ts>_create_discounts.rb`
Follow the `create_whatsapp_accounts` template (`t.references :shop, foreign_key: true`, `jsonb` defaults, timestamps).

```ruby
create_table :discounts do |t|
  t.references :shop, null: false, foreign_key: true, index: true

  # Merchant-facing config
  t.string  :title, null: false
  t.string  :method, null: false              # 'code' | 'automatic'
  t.string  :code                             # null for automatic; unique per shop when present
  t.string  :discount_type, null: false       # 'amount_off' | 'percentage' | 'buy_x_get_y'
  t.decimal :value, precision: 10, scale: 2    # percentage (store as entered, normalize at build) or amount

  # Targeting
  t.string  :applies_to, null: false, default: 'all'   # 'all' | 'products' | 'collections'
  t.jsonb   :product_gids,    null: false, default: []
  t.jsonb   :collection_gids, null: false, default: []

  # BXGY (only when discount_type = 'buy_x_get_y')
  t.jsonb   :bxgy_config, null: false, default: {}      # { buys_type, buys_value, buys_items, gets_items, gets_qty, gets_effect }

  # Requirements / limits / schedule
  t.string   :minimum_requirement_type           # null | 'subtotal' | 'quantity'
  t.decimal  :minimum_requirement_value, precision: 10, scale: 2
  t.integer  :usage_limit                         # code only; null = unlimited
  t.boolean  :once_per_customer, null: false, default: false
  t.datetime :starts_at
  t.datetime :ends_at

  # Combinations
  t.boolean :combines_with_order,    null: false, default: true
  t.boolean :combines_with_product,  null: false, default: false
  t.boolean :combines_with_shipping, null: false, default: true

  # Widget display metadata (ours, not Shopify's)
  t.boolean :widget_enabled, null: false, default: true
  t.string  :headline
  t.string  :unlock_text
  t.integer :display_order, null: false, default: 0

  # Shopify sync state
  t.string :shopify_gid                          # gid://shopify/DiscountCodeNode/... or DiscountAutomaticNode/...
  t.string :sync_status, null: false, default: 'pending'  # 'pending' | 'synced' | 'failed'
  t.text   :sync_error
  t.boolean :is_active, null: false, default: true

  t.timestamps
end

add_index :discounts, [:shop_id, :code], unique: true, where: "code IS NOT NULL"
add_index :discounts, [:shop_id, :is_active]
add_index :discounts, [:shop_id, :widget_enabled]
```

### Model: `app/models/discount.rb`
- `belongs_to :shop`
- Validations: `title` presence; `method` in `%w[code automatic]`; `discount_type` in `%w[amount_off percentage buy_x_get_y]`; `applies_to` in `%w[all products collections]`; `code` presence when `method == 'code'`; `code` must be blank when automatic.
- `enum sync_status: { pending: 'pending', synced: 'synced', failed: 'failed' }`
- Scopes: `active`, `widget_visible` (`active.where(widget_enabled: true).where(sync_status: 'synced')`).
- Guard: BXGY requires `bxgy_config` present.
- `Shop` model: add `has_many :discounts, dependent: :destroy`.

---

## 5. Service layer

New namespace `app/services/shopify_services/discounts/`. One **input builder** + four thin mutation services + delete. Keep mutation strings inline (matches existing convention). Acquire client via `shop.init_session; ShopifyAPI::GraphQL.client` (same as `DiscountCreateService`). Reuse `coerce_value` / `normalize_percentage`.

- `Discounts::InputBuilder` — pure Ruby: `Discount` → the right GraphQL variables hash (`DiscountCodeBasicInput` / `DiscountAutomaticBasicInput` / `DiscountCodeBxgyInput` / `DiscountAutomaticBxgyInput`). Centralizes targeting (`items`), `minimumRequirement`, `combinesWith`, percentage normalization, ISO8601 dates. Single source of truth for the §2 shapes.
- `Discounts::Upsert` — picks create-vs-update based on `discount.shopify_gid.present?`, picks the mutation by `(method, discount_type)`, runs it, parses `userErrors` + GraphQL `errors`, returns `{ ok:, gid:, error: }`. Stores `shopify_gid` + `sync_status`.
- `Discounts::Destroy` — `discountCodeDelete` / `discountAutomaticDelete` by `shopify_gid`; idempotent (treat "not found" as success).
- Error handling mirrors `partial_discount_automatic_app_ensure_service.rb`: check both `response["errors"]` (transport/GraphQL) and the mutation's `userErrors` array; return a structured result, log with `[Discounts::Upsert] shop=… discount=…`.

---

## 6. Background job

`app/workers/shopify_jobs/sync_discount_to_shopify_job.rb` (Sidekiq, mirrors `partial_discount_automatic_app_job.rb`):
- `perform(shop_id, discount_id)` → load shop + discount → `Discounts::Upsert.call` → on success set `sync_status: synced`, `shopify_gid`; on failure set `failed` + `sync_error`.
- Enqueued from the controller after DB save (async). Keeps the request fast and isolates Shopify rate-limit/retry handling.
- A companion `delete_discount_from_shopify_job` (or inline in `Destroy`) for teardown.

**Decision (§11):** async (job) vs inline sync on save. Recommendation: **async**, but have the controller return `sync_status: pending` and the React screen poll/refetch (or optimistic + toast) so the merchant sees "Active" once synced.

---

## 7. Admin API (controller + routes)

- `app/controllers/discounts_controller.rb < AuthenticatedController` (gives `ShopifyApp::Authenticated` + `set_shop`). Actions: `index`, `create`, `update`, `destroy`, plus `activate` / `deactivate` (member routes).
- Strong params: permit the full config (title, method, code, discount_type, value, applies_to, product_gids[], collection_gids[], bxgy_config, minimum_requirement_*, usage_limit, once_per_customer, starts_at, ends_at, combines_with_*, widget_enabled, headline, unlock_text, display_order, is_active).
- Flow: validate → `@shop.discounts.create/update` → enqueue `SyncDiscountToShopifyJob` → render the mirror row (with `sync_status`).
- `destroy`: enqueue/inline `Discounts::Destroy` (delete Shopify object first or mark, then destroy row).
- Routes: `resources :discounts, only: [:index, :create, :update, :destroy] do member { post :activate; post :deactivate } end` (placed with the other authenticated admin routes in `config/routes.rb`).

---

## 8. Admin React screen ("Discounts" in features)

Mirror the `PrepaidDiscount.jsx` feature pattern and the `Context/Store.jsx` tab wiring.

- **Nav:** add a `discounts` tab in `Context/Store.jsx` (`tabs` array + `getIndexFromPath` mapping + render `<Discounts/>`), and the route in `config/routes.rb` (`home#index` catch route for `/features/discounts`).
- **Components** under `app/javascript/packs/Components/Discounts/`:
  - `DiscountsList.jsx` — Polaris `IndexTable`/`ResourceList`: code, type, method, status badge (synced/pending/failed), combinations, active toggle. "Create discount" primary action.
  - `DiscountForm.jsx` — the builder, sectioned to mirror Shopify's own discount UI:
    1. Method: `code` vs `automatic` (segmented). Code field (with "generate" helper reusing `CODK-` style) shown only for code.
    2. Type: amount off / percentage / BXGY (drives conditional fields).
    3. Value (amount vs %); for BXGY the customerBuys/customerGets sub-form.
    4. Applies to: all / specific products / collections → **App Bridge ResourcePicker** for product/collection GIDs.
    5. Minimum requirement: none / subtotal / quantity.
    6. Combinations: 3 checkboxes (order/product/shipping).
    7. Schedule + usage limit + once-per-customer.
    8. Widget display: enabled, headline, unlock_text, order.
  - `utils/discountPayload.js` — client-side payload builder + validation (e.g. percentage 1–100 in UI, normalized server-side).
- **API:** use existing `Services/Api.js` (`Api.get/post/put/delete('/discounts')`) — it already injects the App Bridge id token + CSRF + camel/snake conversion.
- **Status UX:** after create, row shows `pending` → refetch/poll until `synced`. Surface `sync_error` inline if `failed`, with a "retry sync" action (re-enqueues the job).

---

## 9. Storefront widget — **notifik-svelte-app** (coupons + apply)

The live widget is the Svelte app at `notifik-svelte-app/` (Vite → `public/notifik-svelte-app/notifik-svelte.[hash].js`, mounted via iframe, config from `parentWindow.codkingRouteUrl`). It is the newer replacement for the React `app/javascript/packs` widget — **build the coupons feature here.** Most of the plumbing already exists; this is mostly *extension*, not new infra.

### ✅ Apply-path: RESOLVED — Ajax `/cart/update.js`
Confirmed: the widget's primary cart-apply path is the **Ajax Cart API**.
- Apply coupon: `applyCouponService.js` → `applyCoupon(code)` → `otpService.js#executePost({ discount })` → `POST /cart/update.js`.
- Cart read: `otpService.js` → `cartFetch('cart.js')` (returns `discount_codes`, `total_discount`, `total_price`).
- `cartDiscountCodesUpdate` (Storefront GraphQL) exists **only** in `partialPaymentUtils.js` for the partial-payment flow — not our path.
- **No apply-adapter needed.** For **code** discounts, reuse the existing `applyCoupon(code)` essentially as-is. For **automatic** discounts, no apply call (Shopify auto-applies; §3.2).

### Delivering active discounts to the widget
Extend the existing `lightweight_settings` channel (`setting.rb` payload + `script_controller.rb` `/script/lightweight_settings` + metafield sync), which the widget already fetches in `main.js` (`GET /script/lightweight_settings?domain=…`) and normalizes in `settingsMapper.js` into the `otpStore`:
- Add an `active_discounts` array to the payload built from `shop.discounts.widget_visible.order(:display_order)`.
- Per item ship only what the widget needs: `{ id, method, code (code only), discount_type, value, applies_to, product_gids, collection_gids, minimum_requirement_type, minimum_requirement_value, headline, unlock_text }`. **Never** ship internal sync fields.
- **Map it in `settingsMapper.js`** (`active_discounts` → `activeDiscounts`) so it flows through `otpStore.setSettings()` like every other setting.

### Rendering coupons (extend `OffersRewardsSection.svelte`)
`OffersRewardsSection.svelte` already has a coupon-code input + `applyCoupon()` wiring and success/error display. Extend it into a **coupon list** driven by `$otpStore.settings.activeDiscounts`, split into two buckets (per §3.2):
- **code** → "Apply" button → existing `applyCoupon(code)`. To **stack** with an already-applied code, send the merged comma-joined string to `executePost({ discount: "a,b" })` (see clobber risk below), then reflect `discount_codes[].applicable` + totals via the existing `applyDiscountCodeToOtpStore` / `removeDiscountCodeFromOtpStore` helpers in `notifik-svelte-app/src/utilities/otpUtils.js`.
- **automatic** → no apply button; progress / "unlocked automatically" when cheap gates pass.
- Keep the free-form code input too (lets customers type codes not in the list).

### Eligibility (real-time on cart change)
- Recompute on cart change by subscribing to `$otpStore.currentCartData` and/or the existing `codk-cart-discount-updated` custom event (dispatched by `applyCouponService.js`).
- Reuse the **existing rule-filter logic** in `paymentOptionsUtils.js` (it already filters by cart total / products / variants / collections / zipcodes — lines ~539-557) as the model for coupon eligibility; factor the shared predicate into a small `couponEligibility.js` util rather than duplicating.
- Cheap gates (min subtotal, min quantity, date window) → drive "applicable" vs "🔓 add ₹X more to unlock".
- Product/collection-scoped: v1 = optimistic apply + read-back (Shopify is judge). Document the limitation.

### ⚠️ Integration risk — single `discount` field shared with partial-payment rules (BLOCKER)
`/cart/update.js`'s `discount` param holds **the entire** comma-separated code set; each `executePost({ discount })` **replaces** it. The partial-payment flow already writes this field — `paymentOptionsUtils.js` (~lines 868-900, 1116-1120) auto-applies/removes a rule's embedded `discount_code` when a rule is selected. So:
- Applying a merchant coupon must **merge** with any rule-applied code (`"RULECODE,COUPON"`), not overwrite it — and rule selection must not silently drop an applied coupon.
- Define one **single owner** of the `discount` string (a `cartDiscounts` helper that composes rule-code + active coupon codes and is the only caller of `executePost({ discount })`). Resolve this ownership model before wiring the coupon list, or the two features will clobber each other's codes.

---

## 10. Lifecycle & cleanup (avoid the cartpe orphan bug)

We hold `write_discounts`, so we own teardown:
- **Update in app** → `discount*Update` by `shopify_gid` (never create a duplicate).
- **Delete in app** → `discountCodeDelete` / `discountAutomaticDelete` then destroy the row.
- **App uninstall** → in the existing uninstall handler, enqueue deletion of all of this shop's `shopify_gid`s (or at minimum deactivate). *cod-confirm lesson from the cartpe audit: deleting only the local mirror leaves the real Shopify discount live forever.* Decide: hard-delete vs deactivate on uninstall (recommend deactivate, since reinstall may want them back — but document).
- **Drift**: optional v2 — subscribe to `discounts/update|delete` webhooks to catch merchant edits made directly in Shopify admin; v1 can skip and treat our app as the writer of record.

---

## 11. Open decisions (resolve during build)

1. ~~**Apply surface**~~ — **RESOLVED**: widget uses Ajax `/cart/update.js` (`applyCouponService.js`). No adapter needed.
2. **`discount`-field ownership** (§9 blocker): coupon codes and partial-payment rule codes share the single `/cart/update.js` `discount` string. Need one composer/owner so they merge instead of clobber. *Resolve before widget wiring.*
3. **Sync timing**: async job (recommended) vs inline-on-save.
3. **Activate/deactivate**: dedicated activate/deactivate mutations vs toggling `endsAt`.
4. **Uninstall**: hard-delete vs deactivate Shopify discounts.
5. **`customerSelection` vs `context`**: newer API may prefer `context: { all: ... }`; `customerSelection: { all: true }` still works and is what the existing service uses — keep for v1, revisit if deprecation warnings appear.
6. **Product/collection eligibility** in widget: optimistic read-back (v1) vs server-precomputed eligible variant IDs (v2).

---

## 12. Build order (phases)

1. **Data layer** — migration + `Discount` model + `Shop` association. (No Shopify calls; safe.)
2. **Service layer** — `Discounts::InputBuilder`, `Upsert`, `Destroy` + specs against the four mutations. Validate with one real discount per quadrant in a dev store.
3. **Job** — `SyncDiscountToShopifyJob` (+ delete).
4. **Admin API** — `DiscountsController` + routes.
5. **Admin React** — `DiscountsList` + `DiscountForm` + nav wiring + ResourcePicker.
6. **Widget delivery** — add `active_discounts` to `lightweight_settings` payload + metafield sync; map in notifik-svelte `settingsMapper.js`.
7. **Widget render + apply (notifik-svelte)** — resolve the `discount`-field ownership blocker first, then coupon list in `OffersRewardsSection.svelte`, eligibility recompute on `currentCartData` / `codk-cart-discount-updated`, reuse `applyCoupon` (merge codes).
8. **Lifecycle** — delete-on-destroy + uninstall cleanup.
9. **QA** — one discount per quadrant (code/auto × basic/bxgy), combinations vs the partial-payment discount, min-subtotal unlock UX, apply/remove round-trip, uninstall leaves no orphan.

---

## 13. Key files (create / touch)

**Create**
- `db/migrate/<ts>_create_discounts.rb`
- `app/models/discount.rb`
- `app/controllers/discounts_controller.rb`
- `app/services/shopify_services/discounts/{input_builder,upsert,destroy}.rb`
- `app/workers/shopify_jobs/sync_discount_to_shopify_job.rb`
- `app/javascript/packs/Components/Discounts/{DiscountsList,DiscountForm}.jsx` + `utils/discountPayload.js`

**Touch**
- `app/models/shop.rb` (`has_many :discounts`)
- `config/routes.rb` (`resources :discounts` + `/features/discounts`)
- `app/javascript/packs/Context/Store.jsx` (nav tab + route mapping + render)
- `app/models/setting.rb` (`active_discounts` in `lightweight_settings_payload`)
- `app/controllers/script_controller.rb` (no change if payload flows through `setting.rb`)
- App uninstall handler (Shopify-side discount cleanup)

**Touch — notifik-svelte-app (the widget)**
- `notifik-svelte-app/src/utils/settingsMapper.js` (map `active_discounts` → `activeDiscounts`)
- `notifik-svelte-app/src/components/sections/OffersRewardsSection.svelte` (coupon list UI: applicable + locked)
- `notifik-svelte-app/src/services/applyCouponService.js` (reuse `applyCoupon`; merge codes, not replace)
- `notifik-svelte-app/src/utils/paymentOptionsUtils.js` (single owner of the `discount` string; share eligibility predicate)
- `notifik-svelte-app/src/utilities/otpUtils.js` (`applyDiscountCodeToOtpStore` / `removeDiscountCodeFromOtpStore` reflect)
- `notifik-svelte-app/src/stores/otpStore.js` (coupon eligibility state if needed beyond `currentCartData`)
- new `notifik-svelte-app/src/utils/couponEligibility.js` (extracted predicate)

**Reference (do not break)**
- `app/services/shopify_services/discount_create_service.rb` (helpers to copy; do not reuse wholesale)
- `app/services/shopify_services/partial_discount_automatic_app_ensure_service.rb` (idempotency + error-handling pattern; combinations interplay)
