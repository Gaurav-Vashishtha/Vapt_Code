# COD King — COD Form: Product decisions

3 Oct 2026 · Product · answers the 15 questions in `ARCHITECTURE.md` section L

These decisions are final for this release. Numbers are seed defaults; every cap, gate and rate stays editable data in the internal admin. Where a decision changes a seed or default written in `ARCHITECTURE.md`, the line starts with **Change**.

Three items the founder should hear about after the build, because they touch pricing: the launch markets get unlimited form orders on every plan (Q8), overage billing is built but switched off (Q8), and the form charges the COD fee and applies COD rules on the Free plan although the checkout versions of those stay Pro (Q9).

## Decisions

### Q1. Express shipping bug

**Decision.** Leave Express exactly as it is. Do not fix F3 in this project; form orders get their shipping line through the new `form_context` path only.

**Why.** Fixing it raises order totals for existing Express shops without warning.

**Acceptance.** With no `form_context`, `CodOrderCreateService` produces a byte-identical draft order to today's. Record F3 as a separate ticket, to be shipped later with a merchant announcement.

### Q2. COD fee line on form orders

**Decision.** A custom line item titled with the merchant's COD label. No "COD-Fees" product variant on form orders.

**Why.** The fee is in the order at creation, so the total the buyer saw equals the order total, with no order edit and no product per fee amount.

**Acceptance.** Title = `Setting#cod_label`, or "Cash on delivery fee" when blank. Quantity 1, `requiresShipping: false`, taxable only when `general.cod_fee_taxable` is on (default off). The fee is its own line, never merged into the shipping line. `CodFeesService` must not run for form orders (the `_codk_form` guard in F.5).

### Q3. Two embeds

**Decision.** Option (a): warn, do not block. The COD Form goes live even when the old "COD King OTP Block" embed is on. The guard for `app-embed.liquid` is delivered only as the snippet file for the owner's next embed release.

**Why.** `app-embed.liquid` is off limits, and blocking go-live would stop merchants who need the old embed for other features.

**Acceptance.** Show the warning on Setup (banner, tone warning) and in Setup health (`health_legacy_embed_on`) only when the old embed is on **and** (`enable_pre_order_otp` or `partial_payment_enabled`). It does not block the mode switch or the checklist. Copy:

- Title: "The older COD King embed is still on"
- Body: "While "COD King OTP Block" is on, your theme's Buy now and Checkout buttons open Express checkout instead of Shopify checkout. Your Buy with COD button is not affected. If you no longer use Express checkout, turn that embed off in the theme editor."
- Button: "Open theme editor"

### Q4. Post-order verification for form orders

**Decision.** Yes. A form order is treated as a checkout order: a form order that was not OTP-verified gets the shop's post-order verification (SMS, WhatsApp, IVR) exactly as a checkout COD order would. An OTP-verified form order takes the existing verified branch and gets no second verification.

**Why.** ORD-8, and the founder's "don't change the messaging": form orders must not be silently skipped by `skip_draft_order`.

**Acceptance.** Only orders whose `_codkFormSessionId` matches a session with that order id are affected; every other draft order behaves as today. Test orders (`codking_form_test`) send messages like real orders, so the merchant sees the full flow.

### Q5. Payment option step

**Decision.** Full COD is always offered next to the partial option, listed first and preselected. It is removed only when RTO gating or a COD rule removes COD for that buyer.

**Why.** It is the founder's flow (spec section 4, step 8: "full COD or the partial option"), and the buyer tapped a COD button.

**Acceptance.** The step appears only when at least one matching rule is partial or prepaid. If COD is removed and no rule matches, the buyer sees the merchant message and "Pay online". No new setting to hide Full COD in this release.

### Q6. Fee from a COD-type partial rule

**Decision.** The COD fees setting is the only fee on form orders. A COD-type rule's amount is ignored by the form.

**Why.** FEE-1: one fee configuration; two sources would make form totals unpredictable.

**Acceptance.** If the shop has an enabled COD-type rule with amount > 0 and `cod_fee_enabled` is false, Setup health shows an info line: "Your partial payment rules include a COD fee. The COD Form uses the fee from COD fees settings, which is currently off." Link to `/features/cod-fees`. Express keeps using the rule's fee.

### Q7. Postal prefixes and ranges at checkout

**Decision.** Launch form-only with a warning on the Limit COD screen. The checkout function is not changed in this release; its update goes out with the next extension deploy.

**Why.** No change to the live payment function in this release.

**Acceptance.** Under both postal fields, help text: "Prefixes (4000*) and ranges (1000-1999) work in the COD Form only. Shopify checkout matches exact codes." When the **allow** list contains prefix or range entries, show a warning banner: "Prefixes and ranges are not read by Shopify checkout yet. With this list, checkout shows COD only for the exact codes in it." When the allow list has **no** exact code at all, the banner is critical and reads: "This list has no exact postal codes, so Shopify checkout will hide COD for every buyer. Add exact codes, or turn on "COD only through the form"." Saving is not blocked.

### Q8. Cap values

**Decision.** Free plan: 60 form orders a month, then 10 grace orders, then the button opens Shopify checkout. Launch markets: unlimited on every plan. Paid plans have caps that only flag the shop; the form never stops for a paying merchant. Overage billing is built but switched off (rate empty).

**Why.** 60 matches EasySell and Releasit; the launch markets are the acquisition target the founder wants free; billing extra orders to existing subscribers is the one risky money change, so it waits for a data switch.

**Acceptance.** **Change** the J.2 seed to:

| `scope_type` | `scope_key` | `plan_tier` | `monthly_cap` | `at_cap_behaviour` | `grace_orders` | `overage_rate` |
| --- | --- | --- | --- | --- | --- | --- |
| plan | `free` | – | 60 | `grace` | 10 | null |
| plan | `pro` ($9.99) | – | 500 | `flag_only` | null | null |
| plan | `enterprise` ($39, includes `india_budget`) | – | 10,000 | `flag_only` | null | null |
| plan | `enterprise_plus` ($59) | – | null (unlimited) | null | null | null |
| country_group | "Launch markets" (HU, CO, RS, DO, MA, PE, PK) | null (all tiers) | null (unlimited) | null | null | null |

- Global setting stays `at_cap_behaviour: "fallback"`, `grace_orders: 0`, notices at 80% and 100%.
- Free shop timeline: notice at 48 orders (80%) and at 60 (100%); orders 61 to 70 still go through the form; from order 71 the COD button opens Shopify checkout until the next calendar month.
- Planned overage rate when billing is switched on: **USD 0.05 per extra order** on Pro and Enterprise. Do not seed it. It is turned on by editing `overage_rate` after the Billing screen shows the line "After {cap} form orders: $0.05 per extra order" on a real store.
- A flagged paid shop sees: "You have passed {cap} form orders this month. Your form keeps working." with an upgrade button to the next plan.
- Launch-market status follows `shops.country_code`. The unlimited override is reviewed at the end of January 2027; it is data, so no deploy is needed to change it.

### Q9. Feature gates

**Decision.** Everything the competitors give free is free. Paid tiers are for multiple forms, risk tools that use our RTO engine, advanced reporting, CRM integrations and A/B tests. The order cap is the main reason to upgrade.

**Why.** EasySell and Releasit both give upsells, quantity offers, Google Sheets and pixels on their free plan; charging for them loses the comparison.

**Acceptance.** **Change** the J.1 seed to this table (all rows `enabled: true`):

| `feature_key` | `min_tier` | Changed from J.1 |
| --- | --- | --- |
| `cod_form_core` | free | |
| `quantity_offers` | free | |
| `block_lists` | free | |
| `velocity_limits` | free | |
| `basic_analytics` | free | |
| `first_pixel` | free | |
| `abandonment_recovery` | free | |
| `discount_code_field` | free | |
| `custom_fields` | free | |
| `preset_a` | free | |
| `templates` | free | |
| `embedded_mode` | free | |
| `order_bumps` | free | was pro |
| `downsell` | free | was pro |
| `upsell` | free | was pro |
| `google_sheets` | free | was pro |
| `extra_pixels` | free | was pro |
| `pixels_p3` | free | was pro |
| `address_autocomplete` | pro | was free |
| `threshold_offers` | pro | |
| `multiple_forms` | pro | |
| `advanced_analytics` | pro | |
| `klaviyo_omnisend` | pro | |
| `risk_based_otp` | pro | |
| `rto_gating` | pro | |
| `branding_removal` | pro | was enterprise_plus |
| `ab_tests` | enterprise | was pro |

- `quantity_offers` includes the product-page widget (OFF-3). No separate key.
- `branding_removal` is Pro because the rule actually enforced today is Pro and above (`UiCustomizationPlanGuard::BRANDING_PLAN_NAMES`); `Sidekick::PlanCatalog` says Enterprise Plus and is out of date. Do not edit either file in this project.
- Free shops have one form; `multiple_forms` unlocks up to five.
- With `extra_pixels` free, cap pixels at 5 per platform per shop.
- **COD fee and COD rules in the form work on every plan.** The form reads the COD fee setting and the Limit COD rules and applies them to form orders even when the shop is on Free, where the checkout versions run in "test mode". The Pro gate on the existing COD fees and Limit COD screens for Shopify checkout is not changed. On Free, those two screens show: "On the Free plan this applies to COD Form orders. Upgrade to Pro to apply it at Shopify checkout too."
- A gated feature shows a locked card with the plan name and an upgrade button; a downgrade keeps the saved configuration and stops sending it to the storefront.

### Q10. Tax line

**Decision.** Accepted. Shops whose prices exclude tax make the Shopify tax call; tax-inclusive shops never do.

**Why.** ORD-3: the total shown must equal the order total.

**Acceptance.** The tax call runs only when country, province (where the schema needs it) and postal code (where required) are complete, not on each keystroke. While it runs, the tax line shows a loading state and submit is disabled. Results are cached per session by address and cart. The 400 ms quote target (NFR-4) applies to quotes without the tax call; with it the target is 1.2 s at the 95th percentile. If the tax call fails twice, submit proceeds and the server recomputes at order creation; if the total differs, the buyer sees `error_total_changed` with the new total and confirms.

### Q11. Quantity-offer price at checkout

**Decision.** Accepted for now. Use the existing `_codkDiscounts` cart attribute.

**Why.** Same trust model as partial-payment discounts today; the proper fix needs a discount-function release.

**Acceptance.** Form orders are not exposed, because the server recomputes offers. Open a follow-up ticket to move the offer definition into the discount function's own configuration.

### Q12. Bundle apps

**Decision.** Yes. A cart containing bundle lines priced by a cart transform goes to Shopify checkout when the COD button is tapped.

**Why.** A draft order cannot reproduce the bundle price, and a wrong total is worse than no form.

**Acceptance.** The button stays visible and is never dead; the tap goes to checkout with funnel reason `bundle_cart`. Line item properties from bundle apps that do not use a cart transform pass through to the order unchanged.

### Q13. Shopify shipping import

**Decision.** Do not add `read_shipping`. The import button is hidden; CSV import covers the need.

**Why.** A new scope forces every merchant to re-approve the app.

**Acceptance.** No scope change in `shopify_app.rb`. The importer service may exist but is not reachable from the UI.

### Q14. Embed weight

**Decision.** Accepted. 5 KB gzipped for the product page with the default preset; a hard ceiling of 6.5 KB when cart-drawer buttons, sticky bar and Buy now rename are all on.

**Why.** The default path, which most shops use, keeps the founder's "super lightweight" target.

**Acceptance.** Both numbers are enforced in `size-limits.json`; the build fails over either. Extras must be loaded only when enabled, never included in the default path.

### Q15. OTP cannot be sent

**Decision.** After one failed send caused by our side (balance exhausted, shop locked, provider error), the buyer continues and the order is created unverified. The merchant is told.

**Why.** Both competitors let the order through; a buyer should not lose an order because the merchant's SMS balance ran out.

**Acceptance.**
- Applies only to send failures. A throttled send (`otp_throttled`), a blocked phone, a wrong code and exhausted attempts do not bypass OTP; those show the error with "Change number" and "Pay online".
- The unverified order has no verification tag and no `_otpVerifiedPhoneNumber`, so it gets post-order verification under Q4.
- Funnel event reason `otp_unavailable`. The buyer sees no error; the form goes straight to the next step.
- Setup health shows "OTP could not be sent for {count} orders in the last 24 hours. Those orders were placed without verification. Check your message balance." The merchant gets one email per 24 hours at most.

## Other product assumptions

1. **Button defaults.** Label "Buy with COD", no subtitle, no animation, black background with white text, placed below the theme's buy buttons. Sticky mobile button on, same label. Cart and drawer button label "Checkout with COD". Buy now rename empty (unchanged). No hide toggles on.
2. **Form texts.** Title "Cash on Delivery"; submit "Complete order — {total}"; pay online "Pay online instead"; blocked message "Cash on delivery is not available for this order."; no shipping rate "We don't deliver to this address yet."
3. **Default fields.** Shown and required: first name, phone, address, city and province (as the country schema says), postal code (as the schema says). Shown and optional: last name. Off by default: email, address line 2, order note, GST number, marketing consent. **Change** the C.2 seed: `email.enabled` is false. Fewer fields is the conversion default.
4. **Countries and pages.** On first enable, the enabled country list is filled with the shop's own country; the merchant adds others. Product page, cart page and cart drawer are on; quick-buy is off. Hide for out-of-stock is on. "COD only through the form" is off.
5. **OTP.** Follows the shop's existing OTP setting. Send limit = `Setting#max_retries` clamped to 1–5, default 3. Resend wait = `otp_wait_time`, default 30 seconds. OTP mode default "before order".
6. **Fraud defaults.** All velocity limits are off until the merchant turns them on. Prefilled values: 3 orders per phone per 24 hours, 3 per email per 24 hours, 5 per IP per 24 hours. Maximum quantity per order empty (no limit). Minimum time before submit 3 seconds; honeypot on.
7. **Abandoned forms.** 15 minutes, fixed in the UI for now. Active only when the shop already has abandoned-cart messages on. Draft order per abandoned form off by default. No recovery discount by default.
8. **Thank-you.** Shopify order status page by default. If the order has no status URL, show the in-form message "Thank you {first_name}! Your order {order_name} is confirmed."
9. **Downsell.** Shown on the first close, 10% off, once per session, no timer, one active downsell per shop.
10. **Upsell.** One upsell per order (highest priority match). Accept window 5 minutes from order creation; on-screen timer 120 seconds. The COD fee is not recomputed and no message is re-sent.
11. **Limits.** Forms: 1 on Free, 5 with `multiple_forms`. Quantity offers: 50 active, up to 5 tiers each. Order bumps: 20 active, at most 3 shown in a form. Block list: 5,000 entries per kind. Shipping rates: no product limit; the UI pages at 200. A/B test: 4 variants.
12. **Branding and test orders.** Free shops show a small "Powered by COD King" line under the submit button; Pro and above can hide it. Test orders are tagged `codking_form_test`, do not count toward the cap, limits or analytics, and are otherwise real orders the merchant cancels.
