# Admin Dashboard Revamp — Judge.me-style Settings Hub

Status: **Phases 1–2 implemented** (2026-08-17) — hub + registry + 5-item nav are the DEFAULT (`new_admin_nav_enabled?` defaults true; `NEW_ADMIN_NAV_ENABLED=false` or per-shop false opts out); sidebar persists across all settings prefixes via `isHubWrappedPath`; Phase 3 cleanup and Phase 4 self-serve pending
Branch context: `feat/926-new-shopify-cod-king-app-dashboard-revamp`

## Context / problem

The merchant dashboard is cluttered and hard to navigate:

- **Two complete navigation systems** ship side by side behind the `new_admin_nav_enabled?` flag (`app/helpers/application_helper.rb:54`, nav markup in `app/views/layouts/embedded_app.html.erb:30-58`), plus a third vestigial tab-index router still live in `Context/Store.jsx` (`tabs`/`tabsList`/`getIndexFromPath`).
- **No unified Settings screen exists.** Every feature owns its own page and invents its own layout (3-tab pages, annotated sections, long card stacks, DataTable matrices, inline form-replaces-page).
- **Duplicate entry points:** WhatsApp logs in 2 places, Plans in 3, onboarding in 4. Meanwhile `/features`, `/subscription`, `/networks`, `/features/reports` are unreachable from the new sidebar.
- **Merchants depend on support:** ~30 settings are merchant-writable via `POST /settings` but have no UI at all (including the entire IVR confirmation channel).

Goal: reorganize the app around a **Judge.me-style Settings hub** — one screen with a searchable, grouped left sidebar where every USP is a heading and every configurable feature is one click away. **No functionality changes** — existing settings components are re-mounted under the new structure as-is. The Home page stays unchanged.

## Target information architecture

### Outer left nav (Shopify `ui-nav-menu`) — 5 items

| Nav item | Path | Content |
|---|---|---|
| Home | `/` | Unchanged (`SummaryV2` / legacy `Summary`) |
| Settings | `/settings-hub` | **NEW: the grouped Settings hub (this plan)** |
| Analytics | `/usage-analytics` | Existing 6-tab analytics + logs (unchanged) |
| Billing | `/billing` | Existing billing page (unchanged; kept top-level because usage charges are high-traffic) |
| Help & Support | `/help-and-support` | Unchanged |

### Settings hub layout (mirrors the Judge.me Settings screen)

```
┌────────────────────┬──────────────────────────────┐
│ [🔍 Search]        │                              │
│                    │                              │
│ ORDER VERIFICATION │   Content pane renders the   │
│  OTP verification  │   EXISTING component for     │
│  Pre-order OTP     │   the selected item,         │
│  Post-order OTP    │   unchanged                  │
│  Thank-you page OTP│                              │
│  Plus checkout OTP │                              │
│ COD CONTROLS       │                              │
│  COD fees          │                              │
│  Show/hide COD     │                              │
│ PREPAID & CONVERSION                              │
│  Partial payment   │                              │
│  COD to prepaid    │                              │
│  Prepaid discount  │                              │
│  Discounts         │                              │
│  Address prefill   │                              │
│ SMS & WHATSAPP     │                              │
│  WhatsApp account  │                              │
│  Templates         │                              │
│  Campaigns         │                              │
│  Customer notifs   │                              │
│  SMS providers     │                              │
│ INTEGRATIONS       │                              │
│  Google Ads        │                              │
│  Pixel / Meta      │                              │
│ GENERAL            │                              │
│  Plan              │                              │
│  Scheduled reports │                              │
│  Setup guide       │                              │
│  Language          │                              │
│  Advanced          │                              │
└────────────────────┴──────────────────────────────┘
```

### Group → item → existing component mapping (zero rewrites)

| Group | Item | Existing component (mounted as-is) | Old path (kept as redirect) |
|---|---|---|---|
| **Order Verification** | OTP verification (chooser) | `Components/SettingWrapper.jsx` → `OTPPlacementOptions.jsx` | `/features/otp` |
| | Pre-order OTP | `Components/PreOrderSetting.jsx` | `/features/otp/pre-order` |
| | Post-order OTP | `Components/Settings.jsx` | `/features/otp/post-order` |
| | Thank-you page OTP | (current `PostPurchaseHub` tile target) | `/post-purchase` |
| | Plus checkout OTP | `PlusCheckoutOtpExtensionSettings.jsx` | `/features/otp/checkout-extension` |
| **COD Controls** | COD fees | `CODFeesSettings(.New).jsx` (keep existing branch on `codFeeEnabled`) | `/features/cod-fees` |
| | Show/hide COD | `CODShowHide.jsx` | `/features/cod-show-hide` |
| **Prepaid & Conversion** | Partial payment | `PartialPayment/PartialPayment.jsx` (+ add/edit) | `/features/partial-payment` |
| | COD to prepaid | `PrepaidSettings.jsx` (India-gated, as today) | `/features/cod-to-prepaid` |
| | Prepaid discount | `PrepaidDiscount/PrepaidDiscount.jsx` | `/features/prepaid-discount` |
| | Discounts | `Discounts/DiscountsPage.jsx` | `/features/discounts` |
| | Address prefill | `Pages/Hubs/AddressPrefillSettings.jsx` | `/checkout/address-prefill` |
| **SMS & WhatsApp** | WhatsApp account | `Pages/Whatsapp/WhatsappAccountPage.jsx` | `/features/whatsapp/account` |
| | Templates | `WhatsappTemplatesPage.jsx` | `/features/whatsapp/templates` |
| | Campaigns | `WhatsappCampaignsPage.jsx` | `/features/whatsapp/campaigns` |
| | Customer notifications | `Notification.jsx` → `NotificationSettingsTab.jsx` | `/features/notifications` |
| | SMS providers | `Tabs/NetworkSettingTab.jsx` (plan-gated, as today) | `/networks` |
| **Integrations** | Google Ads | `Integrations/GoogleAdsIntegration.jsx` | `/integrations/google-ads` |
| | Pixel / Meta | `Integrations/PixelIntegration.jsx` | `/integrations/pixel` |
| **General** | Plan | `PlansNewDesign.jsx` / `Plans.jsx` branch (existing logic from `Home.jsx`) | `/subscription` |
| | Scheduled reports | `ReportsPage.jsx` | `/features/reports` |
| | Setup guide | `QuickOnboardingV2.jsx` | `/quick-onboarding` |
| | Language | `Integrations/LanguageDropdown.jsx` (`settings.selected_locale`) | (currently buried) |
| | Advanced | NEW simple card — see "Self-serve wins" | — |

Notes:
- WhatsApp logs and abandoned carts stay under **Analytics** only (removes the duplicate at `/features/whatsapp/logs`).
- Existing plan/geo gating stays exactly where it is (component-level), so nothing new is exposed by accident.

## Self-serve wins (the "stop depending on support" payoff)

The settings audit found **~30 fields already merchant-writable via `POST /settings` but with no UI** — support changes them today. The "Advanced" section (and relevant feature screens, in later phases) becomes their home. Highest-value:

- **IVR order confirmation** — the whole channel (`ivr`, `ivr_introduction`, `ivr_confirm_message`, `ivr_cancel_message`) has no dashboard UI; add as an Order Verification item later.
- Per-automation branded WhatsApp template names (`whatsapp_order_confirmation_template`, `_fulfilment_`, `_abandoned_cart_`, `_first_purchase_`, `_cod_verification_`).
- Checkout form toggles: `pre_email_mandatory`, `pre_v2_show_send_code`, `pre_v2_show_tax_info`, `pre_v2_show_shipping_info`, `show_offer_and_reward`.
- COD→prepaid: `prepaid_amount_type`, `prepaid_token_amount`, `prepaid_schedule`.

⚠️ **Bug found during the audit (verify separately, not part of this revamp):** `NotificationSettingsTab` edits `abandoned_template` / `fulfilment_template` / `order_confirmation_template`, but those columns appear to be missing from `setting_params` in `settings_controller.rb` — those saves would silently no-op.

## Architecture (how it stays easy to extend)

**1. Single registry file — the one source of truth** (`app/javascript/packs/Pages/SettingsHub/registry.js`):
each entry `{ id, group, label, icon, path, component, keywords, statusKey }`. The sidebar, the content routing, the search index, and enabled/disabled badges all render from this array. **Adding a future feature = one registry entry + its component.** This kills today's triple duplication (routes.rb / `Home.jsx renderContent()` / `Store.jsx getIndexFromPath()`) for settings screens.

**2. `SettingsHubLayout.jsx`** — two-pane Polaris layout: left column (search `TextField` + grouped nav list built from the registry, selected state from pathname), right content pane rendering the matched component. Search filters items by `label + keywords` client-side, like Judge.me's search box. Reuses existing `navigateTo` from `app/javascript/utils/navigate.js` — **no router library added.**

**3. Routing — minimal, follows existing patterns:**
- Rails: one line, `get '/settings-hub(/*section)', to: 'home#index'` — new sub-paths need no new controllers (existing pattern: `/checkout/*`, `/integrations/*` already point at `home#index`). The `settings-hub` prefix avoids collisions with the existing `resources :settings` JSON API (`POST /settings`, `GET /settings/provinces`, …).
- React: one new branch in `Home.jsx renderContent()`: `pathname.startsWith('/settings-hub')` → `<SettingsHub/>`; the hub resolves the sub-path against the registry internally.
- Old paths keep working: their existing `Home.jsx` branches stay, so deep links, back-actions, and SaveBar dirty-tracking (`contextualBar` in `Context/Store.jsx`) are untouched.

**4. Rollout safety:** gate the new outer nav + hub behind the existing `new_admin_nav_enabled?` mechanism (ENV global + per-shop `shops.new_admin_nav_enabled`), or a sibling flag, so it can be enabled per-shop first.

**5. Reuse, don't rebuild:** `SectionHub.jsx` tiles, `DocumentationCard.jsx` (right-rail help), `SummaryV2` cards, and the existing `data-i18n-key` nav translation all carry over. The four hub pages (`CheckoutHub`, `MessagingHub`, `PostPurchaseHub`, `CheckoutEnhancementsHub`) remain temporarily as landing pages and can be retired once the Settings hub is default.

## Implementation phases (each separately approvable)

1. **Phase 1 — Scaffold:** registry + `SettingsHubLayout` + Rails route + `Home.jsx` branch; mount all existing components per the mapping table; add "Settings" to the new `ui-nav-menu` block in `embedded_app.html.erb`.
2. **Phase 2 — Consolidate:** slim outer nav to the 5 items; redirect old paths (`/features`, `/subscription`, `/networks`, `/features/*`) into their `/settings-hub/...` equivalents; fix hardcoded "Back to Features" back-actions (`PartialPayment.jsx:481`, `PrepaidSettings.jsx:700`).
3. **Phase 3 — Cleanup (optional, later):** retire the legacy `tabs`/`tabsList` index router in `Store.jsx`, dedupe `HubTile`/`FeatureTile`/`SectionCard`, remove orphaned screens (`/features/whatsapp/audience` placeholder, `/orders/bulk-verify` fallthrough, commented-out components).
4. **Phase 4 — Self-serve (later):** build the "Advanced" section and surface the no-UI settings listed above.

**Explicitly out of scope:** any behavior/functionality change, splitting the monster files (`PreOrderSetting.jsx` 2,240 lines etc.), the storefront widget, internal admin dashboards, onboarding redesign.

## Verification (for the implementation)

- Flag off: app identical to today (both navs, all routes).
- Flag on: every mapping-table item loads its screen inside the hub; save via SaveBar works on each (`POST /settings` unchanged); search filters the sidebar; old deep links land correctly; browser back works with the hand-rolled `pushState` router.
- Test on dev store `test-sso-store-11` via ngrok.
