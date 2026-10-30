---
name: built-for-shopify
description: Check the app against Shopify's Built for Shopify requirements (shopify.dev/docs/apps/launch/built-for-shopify/requirements) before or after implementing anything that touches admin navigation, embedded-app behavior, onboarding, design/UI patterns, storefront or checkout performance, or app-store/compliance concerns. TRIGGER whenever the user says "compliance", "Built for Shopify", "BFS", "app store requirements", "app review", or whenever a change touches app/views/layouts/embedded_app.html.erb, the Settings hub / admin nav (app/javascript/packs/Pages/Home.jsx, Pages/SettingsHub), onboarding flows (QuickOnboarding*), Polaris usage, App Bridge, or the storefront widget's Lighthouse/performance footprint. Re-check this before telling the user a UI or nav change is "done" — several rejection reasons are easy to reintroduce without noticing (nav highlighting, back buttons, banner stacking).
---

# Built for Shopify requirements

Source: https://shopify.dev/docs/apps/launch/built-for-shopify/requirements
(re-`WebFetch` it before relying on numbers here for anything load-bearing —
this file is a snapshot from 2026-09-17 and Shopify revises these).

## Does COD King match one of the 14 app categories?

The page lists 14 categories (Ads, Affiliate Program, Analytics, Carrier
Services, Discount, Email Marketing, Forms, Fulfillment Services,
Invoices/Receipts, Product Bundles, Product Reviews, Returns/Exchanges, SMS
Marketing, Subscription) with their own extra requirements. **COD King does
not cleanly match any of them** — it's a COD/checkout-verification app, which
isn't one of the 14. Two features brush against listed categories without the
app being classified there:

- The Branded WhatsApp / SMS notification features overlap **SMS Marketing
  apps** (§5.13: Web Pixels instead of script tags, customer data sync,
  Shopify segments, visitors API) — worth checking that section when touching
  `app/services/merchant_whatsapp/`, SMS templates, or notification consent.
- Nothing here matches **Discount apps** (§5.5) even though the app applies
  discounts via `PartialRuleSet` / order edits — those requirements are about
  Shopify's own discount functions/APIs for apps whose *product* is discounting,
  which doesn't apply to a COD-verification app that happens to apply a
  discount as a side effect.

Don't assume a category applies without re-reading its section — the mapping
above is a starting point, not a ruling.

## What does apply: sections 1-4 (every embedded app)

### 1. Prerequisites
- App Store requirements met, good Partner standing, no active infractions.
- Merchant utility: 50+ net installs from active paid-plan shops, 5+ reviews,
  a minimum recent rating.

### 2. Performance
- **2.1 Admin Web Vitals** (75th percentile, min. 100 calls / 28 days):
  LCP ≤ 2.5s, CLS ≤ 0.1, INP ≤ 200ms. Relevant to every React admin screen
  under `app/javascript/packs/` — a heavy `useEffect` chain or an unbounded
  layout shift on Settings hub navigation is exactly what this measures.
- **2.2 Storefront performance**: must not drop the storefront Lighthouse
  score by more than 10 points. Relevant to the checkout/OTP widget
  (`notifik-svelte-app`) and any theme app extension / script tag.
- **2.3 Checkout performance**: p95 ≤ 500ms, ≤ 0.1% failure rate (min. 1000
  requests / 28 days) for anything in the checkout path — carrier services,
  checkout UI extensions (`extensions/`), the COD Shopify Plus checkout OTP
  extension.

### 3. Integration
- Embedded apps load the **latest App Bridge** via the `app-bridge.js` script
  tag (already the pattern in `embedded_app.html.erb`) and use **ID token
  authentication**.
- Merchants must be able to complete primary workflows **inside the embedded
  admin** — no bouncing to an external site for core setup.
- Sign-up must not require an extra login.
- The app home page must **expose key metrics**.
- Any setting that controls the Shopify↔third-party connection must live
  **inside the embedded app**, not only on an external dashboard.
- Theme changes go through **theme app extensions**; the app must not add,
  remove, or edit a merchant's theme files directly (three narrow exceptions
  exist on the page — check them before assuming an edit is one).

### 4. Design — the one with the most ways to silently regress

**Familiar** (11 listed rejection reasons — the ones most relevant here):
- Sub-page navigation highlighting must work correctly, and there must be no
  separate "homepage" nav item distinct from the main Summary. **This is
  exactly what the /settings-hub URL-prefix fix addressed** (see commit
  `9136b32a` / [hubUrl.js](../../../app/javascript/packs/Pages/SettingsHub/hubUrl.js))
  — App Bridge highlights a nav item by matching the current URL against the
  nav link's `href`, and a sub-page whose URL doesn't fall under any nav
  link's path shows no highlight at all. Re-check this any time a new
  settings screen is added outside `WRAPPED_PREFIXES` in
  [registry.js](../../../app/javascript/packs/Pages/SettingsHub/registry.js).
- The app must use the **Shopify nav menu**, not build its own — this repo's
  `<ui-nav-menu>` in `embedded_app.html.erb` is the correct pattern; don't
  reintroduce an in-app sidebar as the *only* navigation.
- Every sub-page needs a **back button** (App Bridge breadcrumb or in-page).
- Content in card-like containers, Polaris button styles, no serif/script
  fonts, body text size and background color close to Shopify's own, WCAG 2.1
  AA text contrast, consistent iconography.
- Mobile: no required horizontal scroll, no content that's mobile-inaccessible
  or unreasonably condensed (e.g. a two-column layout that never collapses —
  check any `InlineGrid`/`InlineStack` added without a responsive `columns`
  prop against this).

**Helpful**:
- No spelling/grammar errors in headings, nav, or CTAs — worth a pass over
  `config/localeJson/en.json` additions.
- Onboarding must guide merchants to completion, be concise, be easy to find,
  never imply installing another app, only ask for merchant info that's
  justified, and be removable once done — relevant to `QuickOnboarding*.jsx`.
- The home page must show activation status of any block/embed and surface
  helpful metrics, not just static content.
- Errors: must not auto-dismiss, must render in red, must appear where the
  problem is (not just a red field with no message), and only after the
  merchant has interacted (not shown pre-emptively).
- The most prominent button in a group must represent the logical next
  action.
- Any live visual customization (the checkout OTP widget preview, the popup
  branding preview added in `CustomSetup.jsx`) must show a **live preview**,
  and on desktop, editor and preview must both be visible at once.

**User-friendly**:
- No outcome-guaranteeing language, no false claims about third-party apps.
- No countdown timers or guilt-driven CTAs pressuring upgrades.
- No auto-appearing modals/popovers, no large elements dramatically animating
  in, no red used outside error/destructive contexts.
- No single giant ungrouped form; no two banners stacked close together; keep
  copy concise over walls of text.
- App icon must not be mistakable for a first-party Shopify app; don't reuse
  Shopify Sidekick's icon or "magic purple" for AI-flavored features.
- Promotional content must be dismissible. Plan-gated features must be
  visibly and functionally disabled with a clear indicator (this repo already
  does this in places — e.g. the Enterprise Plus branding-removal gate in
  `CustomSetup.jsx` — match that pattern for new gated features). Plus-only
  features must be hidden entirely for non-Plus merchants.

## How to use this

1. Before implementing a nav, onboarding, settings-page, or storefront-facing
   UI change, skim the relevant bullets above.
2. After implementing, re-check the ones about nav highlighting, back
   buttons, and banner/popup stacking specifically — they're the easiest to
   break without any test catching it, since nothing here is covered by an
   automated test suite (per this project's CLAUDE.md: "No specific test
   commands found").
3. For anything ambiguous or high-stakes (a new category-adjacent feature,
   API version behavior), `WebFetch` the live page rather than trusting this
   summary — it's a snapshot, and Shopify revises these requirements.
4. Pair with the [docs-lookup](../docs-lookup/SKILL.md) skill when the change
   also touches App Bridge, Polaris, or the Admin API directly.
