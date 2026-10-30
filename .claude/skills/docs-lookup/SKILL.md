---
name: docs-lookup
description: Check current official documentation for React, Svelte, Shopify (Admin GraphQL API, App Bridge, Polaris, Liquid/theme app extensions, webhooks, shopify_app gem) before implementing or answering questions about them, instead of relying on training-data memory, which is often stale for these fast-moving APIs. TRIGGER before writing or reviewing code that touches app/javascript/packs (React 18 + Polaris 12 admin), notifik-svelte-app or extensions/**/src (Svelte 5), config/initializers/shopify_app.rb or anything calling ShopifyAPI/GraphQL/webhooks/App Bridge, and before answering any question that names React, Svelte, Shopify, Polaris, App Bridge, GraphQL Admin API, Liquid, theme app extension, checkout extension, or webhook. SKIP for pure Ruby/Rails-only, SQL, or infra-only changes that touch none of the above.
---

# Docs lookup before answering

This repo moves across fast-changing surfaces (Shopify's Admin API ships a new
version every quarter, App Bridge v4 replaced the Redirect-action pattern this
codebase used to use, Svelte 5 replaced Svelte 4's reactivity model). Guessing
from training data on any of these is a common source of wrong answers here —
check the current docs first, then answer or implement.

## What this repo is pinned to

Check these before assuming a version-specific answer is still correct — they
drift, so re-grep rather than trusting this file blindly:

- **React**: `18.2.0` ([package.json](../../../package.json))
- **Svelte**: `5.39.x`, runes mode (`notifik-svelte-app/package.json`) — this is
  the storefront widget (`notifik-svelte.*.js`), not the admin.
- **Shopify Admin GraphQL API**: `2025-07` (`config/initializers/shopify_app.rb`)
- **shopify_app gem**: `18.1.2` (`Gemfile`)
- **App Bridge**: v4, loaded via `<script src="https://cdn.shopify.com/shopifycloud/app-bridge.js">`
  in [embedded_app.html.erb](../../../app/views/layouts/embedded_app.html.erb) — NOT
  the older `@shopify/app-bridge-react` Provider/Redirect-action pattern, though
  that npm package (`^4.2.8`) is still a dependency for its React hooks.
- **Polaris**: `12.6.0` (`@shopify/polaris` in package.json)

## How to check

- **React / Svelte**: use the `mcp__claude_ai_Context7__resolve-library-id` /
  `mcp__claude_ai_Context7__query-docs` tools. For React use library id
  `/reactjs/react.dev`; for Svelte use `/sveltejs/svelte` pinned to a `5.x`
  version, or `/websites/svelte_dev` for the prose guide (runes, `$state`,
  `$derived`, `$effect` — this codebase's Svelte files use runes, not the old
  `export let` / `$:` style, except where legacy files haven't been migrated,
  so check the actual file before assuming which style applies).
- **Shopify (Admin API, App Bridge, Polaris, webhooks, extensions, Liquid,
  theme app extensions, checkout UI extensions, Built for Shopify)**: use
  `WebFetch` directly against `shopify.dev` — Context7's Shopify coverage is
  thin and not reliably version-pinned for an API that revs every quarter.
  Useful entry points:
  - Admin GraphQL API reference: `https://shopify.dev/docs/api/admin-graphql/2025-07/...`
  - App Bridge: `https://shopify.dev/docs/api/app-bridge-library`
  - Polaris components: `https://polaris.shopify.com/components/...` or
    `https://shopify.dev/docs/api/app-home/polaris-web-components` (Polaris web
    components are a separate, newer surface from the React library — check
    which one a given file actually imports before citing either).
  - Webhooks: `https://shopify.dev/docs/api/webhooks`
  - Extensions (checkout UI, theme app, web pixel — this repo has all three
    under `extensions/`): `https://shopify.dev/docs/api/checkout-ui-extensions`,
    `https://shopify.dev/docs/apps/build/online-store/theme-app-extensions`,
    `https://shopify.dev/docs/api/web-pixels-api`

## Doing this well

1. Look up the doc before proposing an approach, not after — a wrong first
   guess (e.g. "App Bridge Redirect action" instead of `history.pushState` +
   `popstate`, which this codebase deliberately moved away from — see
   [navigate.js](../../../app/javascript/utils/navigate.js)) wastes a
   correction round-trip.
2. When a doc conflicts with what the existing code does, say so explicitly —
   the existing pattern usually wins for consistency, but flag it rather than
   silently picking one.
3. For anything that could affect **Built for Shopify** eligibility or the
   app's listing/compliance status (admin navigation, embedded-app behavior,
   onboarding, checkout/storefront performance, design patterns) — load the
   [built-for-shopify](../built-for-shopify/SKILL.md) skill as well, not just
   this one.
4. Cite what you checked in your answer (the doc URL or Context7 library id),
   briefly — enough that a reader can tell you looked, not a wall of quotes.
