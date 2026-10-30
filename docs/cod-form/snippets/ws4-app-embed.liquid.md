# WS4 snippet — guard for the Express embed (`app-embed.liquid`)

**File:** `payment-customization-js/extensions/cod-king-otp-extension/blocks/app-embed.liquid`
**Owner:** the embed's owner. Not applied in this project (the file is off limits; ARCHITECTURE.md G.2, product decision Q3).
**When:** the owner's next embed release.

## Why

While "COD King OTP Block" is on and `enable_pre_order_otp` or `partial_payment_enabled` is true, it
intercepts the theme's Buy now and Checkout clicks and opens Express. In COD Form mode those buttons
must go to Shopify checkout (prepaid path), and in preset A the new embed handles Buy now itself.
The guard makes the old block print nothing when the shop is in COD Form mode.

## What to insert

1. Directly **before the first line** of the block body (line 1 of the file, before any HTML, `<script>` or Liquid output):

```liquid
{%- unless shop.metafields.codk.cod_form.value.enabled -%}
```

2. Directly **before `{% schema %}`** (currently line 2612):

```liquid
{%- endunless -%}
```

Nothing else changes. The `{% schema %}` block must stay outside the guard.

## What the guard does not cover

The schema of the old block has `"javascript": "script.js"` and `"stylesheet": "style.css"`. Shopify
loads those two assets whenever the block is switched on, whatever the Liquid prints, so they still
load in COD Form mode. `script.js` must therefore tolerate the globals of the block body being absent.
Check that before releasing the guard; if it does not, add at the very top of `assets/script.js`:

```js
if (window.__CODKF__) { /* COD Form mode: the Express embed is inactive */ }
else {
  // … existing file body …
}
```

(`window.__CODKF__` is set by the COD Form embed only when it is active on the page. On pages where
the COD Form embed prints nothing — a country that is not enabled, for example — Express then keeps
working as today, which is the wanted behaviour.) Note the difference: the Liquid guard switches
Express off for the whole shop in COD Form mode; the JS guard only where the form is active on the
page. Choose one rule with product before release; this project ships with neither applied and
with the Setup warning `legacy_embed_on` instead.

## How to verify

- Shop with `codk.cod_form.enabled = true`: view source of a product page → no output from "COD King
  OTP Block"; Buy now goes to Shopify checkout.
- Shop without the metafield, or with `enabled: false`: output byte-identical to today.
