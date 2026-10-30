# COD King — COD Form Requirements Spec

Oct 3, 2026 · @Avijeet

This spec defines the COD Form module for COD King: a merchant-designed order form with its own Buy with COD button, shipping rates and offers. It launches to all merchants, and prepaid always goes to Shopify checkout. Requirement IDs are stable; phase tags are P1 (launch), P2 and P3.

## 1. Decisions locked

These are settled by the founder and are inputs to this spec, not review items.

| Topic | Decision |
| --- | --- |
| Packaging | A module inside the existing COD King app. No separate app listing. |
| Audience | All merchants at launch, India included. |
| Prepaid | The COD Form takes no payments. Every prepaid path goes to Shopify checkout. |
| In-form payments | Belong to RabbitPay, which is deployed separately and is out of scope. |
| Free plan | A monthly form-order cap that is configurable without a deploy. |
| EasySell | Messaging partnership only. No dependency and no conflict. |
| Storefront code | The form is a separate, new implementation with its own bundle. It is not built or managed inside the existing Svelte app. The backend stays in the existing Rails app (`cod-confirm`). |
| Storefront delivery | The COD button and every form element are created only by the app embed, and only for the features that are enabled. No app blocks. |
| Weight | The storefront code is as light as possible; conversion comes before features. Budgets are in section 15. |
| Buy now button | The theme's Buy now button stays. The merchant can rename it, for example to "Buy with prepaid". |
| Partial payment | Enabled partial payment rules apply to form orders, as a payment option step after the form. |
| OTP | When OTP is enabled, verification happens after the address form is submitted. |
| Existing merchants | The current OTP-first modal ("Express checkout") keeps working. No forced migration. |
| Dashboard placement | COD Form is a new group in the in-app Settings sidebar. Nothing is added to the Shopify admin navigation. |

## 2. Scope

**Goals**

- Give merchants a COD order form they design themselves, opened by COD King's own button.
- Raise order value with quantity offers, order bumps, upsells and downsells.
- Reuse what COD King already has: order creation, OTP, RTO scoring, COD rules, messaging, billing.
- Reach parity with EasySell and Releasit on the form, and keep RTO scoring and own-number WhatsApp as differentiators.
- Support the launch markets (Hungary, Colombia, Serbia, Dominican Republic, Morocco, Peru, Pakistan) and India from day one.

**Non-goals**

- Taking payments inside the form.
- Replacing Shopify checkout for prepaid orders.
- Building a bundles product. Third-party bundle apps are passed through (OFF-9).
- Retiring Express checkout in this project.

**Storefront modes.** A shop is in exactly one mode. The mode is stored per shop and set on the COD Form Setup screen.

| Mode | Behaviour | Status |
| --- | --- | --- |
| Shopify checkout + COD rules | Native checkout; COD King applies fee, show/hide and OTP there | Existing |
| Express checkout | OTP-first modal: phone, OTP, saved address, payment choice | Existing |
| COD Form | Single-page form opened by the Buy with COD button | New, this spec |

Switching mode must not delete the configuration of the other modes.

## 3. Button strategy

The merchant picks a preset on the Buttons screen. Preset B is the default for every shop, and the merchant can change it at any time.

| Preset | Product page buttons | Where prepaid goes | Default and phase |
| --- | --- | --- | --- |
| B. COD button + Buy now | The embed adds "Buy with COD". The theme's Buy now is unchanged, or hidden by the merchant | Shopify checkout, from the theme's Buy now | Default for everyone, P1 |
| C. COD button + renamed Buy now | The embed adds "Buy with COD" and relabels the theme's Buy now with the merchant's text, for example "Buy with prepaid" | Shopify checkout, from the renamed Buy now | Opt-in, P1 |
| A. Single button | The theme's Buy now opens the form; the buyer picks COD or Pay online inside | Shopify checkout, from the form's Pay online option | Opt-in, P2 |

**Prepaid share.** A visible COD button makes COD more prominent. Merchants who want to push prepaid use preset C: the renamed Buy now button carries the prepaid message, and can show the prepaid discount once PRE-2 ships. Prepaid share is tracked as a guardrail (section 16).

**Rules that apply to all presets**

- The COD button is created only by the app embed. There is no app block and no theme code edit.
- The embed adds the button only when COD Form mode is on and the page passes the visibility rules. It loads only the code that the enabled features need.
- The theme's Buy now button is never replaced. It can be renamed or hidden.
- Add to cart stays visible unless the merchant hides it.
- A button is never dead. If the form cannot open (cap reached, config error, script failure), the tap goes to Shopify checkout.
- If the product fails a COD rule known at page load (product, collection, price), the COD button is not rendered.
- A buyer who fails a rule known only later (postal code, RTO risk) is told inside the form and pointed to prepaid checkout.

## 4. Buyer flow

The form is one screen. OTP, the payment option and the upsell are follow-up steps in the same popup, each shown only when it applies.

1. **Tap.** The buyer taps the COD button on the product page, cart page or cart drawer. From the product page the form holds the selected variant and quantity; from the cart it holds the whole cart.
2. **Session.** The client requests a signed form session. The server returns the published form config, eligibility and the order-cap state.
3. **Summary and quantity offer.** Items, variant, quantity and any quantity-offer tiers sit at the top.
4. **Contact and address.** Fields follow the selected country's schema.
5. **Shipping and extras.** Qualifying shipping rates, order bumps and the discount code field. Totals come from the server quote and update on every change.
6. **Submit the form.** No order exists yet if step 7 or 8 applies.
7. **OTP**, if OTP is enabled. The code goes to the phone number entered in the form. The buyer can go back and correct the number without losing the form.
8. **Payment option**, if an enabled partial payment rule matches the cart. The buyer chooses full COD or the partial option. Partial continues in the existing partial payment flow with the details already entered.
9. **Order created** for full COD.
10. **One-click upsell**, if configured. Accepting adds the item to the order just created.
11. **Thank-you**, per the merchant's setting.

**Side paths**

- **Close.** A downsell is shown if configured. If a phone or email was entered, the session becomes an abandoned form after 15 minutes.
- **Blocked.** A buyer who hits a block list, an order limit or a COD rule sees the merchant's message and the Pay online option.
- **High RTO risk.** COD is replaced by Pay online or Pay advance (P2).

## 5. Requirements: buttons and visibility

| ID | Requirement | Phase |
| --- | --- | --- |
| BTN-1 | The COD button is created only by the app embed. There is no app block and no theme code edit. | P1 |
| BTN-2 | Placement: directly below the theme's buy buttons by default. The merchant can choose above or below, or give a custom CSS selector. | P1 |
| BTN-3 | Conditional output: the embed renders nothing and loads no form code when COD Form mode is off or the page is not eligible. It loads only the modules for enabled features. | P1 |
| BTN-4 | Sticky mobile button, shown when the main button is out of view. Can be turned off. | P1 |
| BTN-5 | Cart page and cart drawer button that opens the form with the whole cart. | P1 |
| BTN-6 | Button styling: label, subtitle, text and background colour, border, radius, shadow, icon, animation (none, pulse, shake). The label supports `{total}`. | P1 |
| BTN-7 | Presets B and C from section 3, selectable on one screen with a live preview. | P1 |
| BTN-8 | Rename the theme's Buy now button: the merchant enters the label, for example "Buy with prepaid". Empty means unchanged. The label survives variant changes and theme re-renders. The button's behaviour is untouched. Buy now buttons are found with the same detection the app embed uses today; Shopify-branded express buttons are left as they are. | P1 |
| BTN-9 | Separate toggles to hide the theme's Add to cart, Buy now, Checkout and express wallet buttons. | P1 |
| BTN-10 | Open hooks for page builders and links: CSS class `codking-open-form` and `window.CODKing.openForm({variantId, quantity})`. Documented for GemPages, PageFly and Zipify. | P1 |
| BTN-11 | The button reads the variant and quantity selected on the page at tap time and reacts to variant changes. | P1 |
| BTN-12 | Preset A: the theme's Buy now opens the form. Implemented in the new embed code, not through the existing Express checkout interception. | P2 |
| VIS-1 | Enable per page type: product page, cart page, cart drawer, quick-buy on home and collection pages. | P1 |
| VIS-2 | Enable for all products, or for selected products and collections, with exclude lists. | P1 |
| VIS-3 | Enable per country. Buyers outside the enabled countries get native checkout. | P1 |
| VIS-4 | Order total minimum and maximum, with an optional message when out of range. | P1 |
| VIS-5 | Hide the COD button for out-of-stock variants. | P1 |
| VIS-6 | Do not render the COD button for products that fail a COD rule known at page load. | P1 |

## 6. Requirements: form, fields and designer

| ID | Requirement | Phase |
| --- | --- | --- |
| FRM-1 | Single-page popup: bottom sheet on mobile, centred modal on desktop. | P1 |
| FRM-2 | Default block order: order summary, quantity offer, contact, address, shipping options, order bumps, discount code, totals, submit. | P1 |
| FRM-3 | Per field: show or hide, required or optional, label, placeholder, error text. | P1 |
| FRM-4 | Order summary shows image, title, variant, price, compare-at price and a quantity selector. | P1 |
| FRM-5 | Address fields follow a per-country schema: country (when more than one is enabled), province or state dropdown, city dropdown where a dataset exists, postal code required or optional. | P1 |
| FRM-6 | India address schema, used only when the buyer's country is India: pincode fills city and state, pincode validity check, optional GST number (existing field and validation). | P1 |
| FRM-7 | Validation: phone length and prefix per country, email format, required fields. Leading zero stripped from phone where the country needs it. | P1 |
| FRM-8 | Design settings: primary colour, text colour, background, corner radius, header title, logo. Font inherits from the theme. | P1 |
| FRM-9 | Right-to-left layout when the storefront locale is RTL. | P1 |
| FRM-10 | Every buyer-facing string is editable. Defaults ship in English, Hindi, Arabic, French, Spanish, Hungarian, Serbian and Urdu. | P1 |
| FRM-11 | Draft and publish. The designer shows a live desktop and mobile preview of the draft; the storefront only reads the published version. | P1 |
| FRM-12 | Reorder fields and blocks by drag and drop. | P2 |
| FRM-13 | Custom fields: text, text area, dropdown, radio, checkbox, date. Values are saved on the order as additional details. | P2 |
| FRM-14 | Content blocks: rich text, image or GIF, trust badges. | P2 |
| FRM-15 | Per-field regex validation and a Latin-characters-only option. | P2 |
| FRM-16 | Discount code field that validates against Shopify discounts and shows the result in totals. | P2 |
| FRM-17 | Marketing consent checkbox, written to the customer's SMS and email marketing consent. | P2 |
| FRM-18 | Optional phone-first variant: phone, then OTP, then autofill of a saved address from the existing prefill backend. Off by default; the default order is address form, then OTP. A saved address is never shown before OTP succeeds. | P3 |
| FRM-19 | Per-locale text sets, selected by the storefront locale. | P2 |
| FRM-20 | Embedded mode: the form renders inline on the product page, placed by the app embed. | P3 |
| FRM-21 | At least four design templates. | P3 |
| FRM-22 | Up to five forms per shop, each targeted to products or collections, with one default. | P3 |
| FRM-23 | Countdown timer block. | P3 |

## 7. Requirements: shipping, fees and prepaid hand-off

| ID | Requirement | Phase |
| --- | --- | --- |
| SHP-1 | A rate table for the form: name, description, price. No limit on the number of rates. | P1 |
| SHP-2 | Rate conditions: order total, weight and quantity ranges; country; province list. | P1 |
| SHP-3 | Free shipping as a rate with conditions. | P1 |
| SHP-4 | One qualifying rate is preselected and the selector can be hidden. No qualifying rate blocks submit with a merchant message. | P1 |
| SHP-5 | Rates are re-evaluated when address, quantity or offer changes. | P1 |
| SHP-6 | Rate conditions by product: apply only to, or exclude, selected products. | P2 |
| SHP-7 | One-time import of rates from the shop's default Shopify shipping profile. | P2 |
| SHP-8 | CSV import of province-wise rates. | P2 |
| FEE-1 | COD fee, fixed or percentage, with a label, shown as its own line in totals. It reads the existing COD fee setting; there is one fee configuration for form and checkout. | P1 |
| FEE-2 | Option to apply tax to the COD fee. | P2 |
| PRE-1 | Prepaid hand-off (preset A and blocked buyers): create a Shopify checkout with the cart lines and the contact and address already entered, then redirect. Implemented in the new form code. | P1 |
| PRE-2 | Prepaid discount through the existing discount function, triggered by a cart attribute. Its value is available to the renamed Buy now label and to form labels. | P2 |
| PRE-3 | "COD only through the form": hides COD at Shopify checkout using the existing payment customization. Off by default. | P1 |
| PRE-4 | Existing partial payment rules (`PartialRuleSet`) apply to form orders. The server evaluates enabled rules against the cart in the quote. | P1 |
| PRE-5 | Prices are shown, and the order is created, in the buyer's presentment currency under Shopify Markets. | P1 |
| PRE-6 | A documented hand-off event and payload at the Pay online step, so RabbitPay can take over prepaid where it is installed. Interface only; no RabbitPay work in this project. | P3 |
| PRE-7 | Payment option step: after the form is submitted, and after OTP when enabled, a matching rule shows a step with full COD and the partial option, each with the amount to pay now and the balance on delivery. | P1 |
| PRE-8 | The step shows exactly the options the matched rule allows. If no enabled rule matches, the step is skipped and the COD order is created. | P1 |
| PRE-9 | Choosing partial hands the buyer to the existing partial payment flow with cart, contact and address carried over. That flow collects the advance and creates the order; the form does not. The hand-off works as it does today: the form sets the buyer identity on the cart and passes the cart on. | P1 |
| PRE-10 | Partial orders that start in the form are tagged as form orders, count toward the order cap and appear in form analytics. | P1 |

## 8. Requirements: OTP, fraud and COD rules

COD rules are configured once and enforced in two places: the form (server-side, at quote and at submit) and Shopify checkout (the existing payment function). Engineering must not create a second rule store for the form.

| ID | Requirement | Phase |
| --- | --- | --- |
| OTP-1 | The form honours the shop's existing OTP setting. When OTP is enabled, the OTP step comes after the address form is submitted and before the order is created, using the phone number entered in the form. | P1 |
| OTP-2 | Reuse existing providers, templates and channels (SMS, WhatsApp). Resend and a configurable attempt limit of 1 to 5. | P1 |
| OTP-3 | Verified orders get the shop's existing verification tag. | P1 |
| OTP-4 | From the OTP step the buyer can go back to correct the phone number; the form keeps everything entered. | P1 |
| OTP-5 | Closing at the OTP step creates no order. The session counts as an abandoned form (ABN-1). | P1 |
| OTP-6 | Optional mode: create the order first and tag it when verified. | P2 |
| OTP-7 | Risk-based mode: OTP only when the RTO engine returns the medium band. | P2 |
| RUL-1 | The form evaluates the same COD rules as checkout: country, province, postal code, product, collection, vendor, cart total. | P1 |
| RUL-2 | Postal code allow or deny lists accept single codes, prefixes and numeric ranges, by text entry or file upload. | P1 |
| RUL-3 | RTO gating: in the high band, full COD is removed and the buyer is offered partial payment (when a rule allows it) or prepaid checkout, with a merchant message. Thresholds are per shop. | P2 |
| FRD-1 | Block lists for phone, email and IP, with a custom message for blocked buyers. | P1 |
| FRD-2 | Limits: at most N orders per phone, per email and per IP within X hours. Each is set separately. | P1 |
| FRD-3 | Maximum total quantity per order. | P1 |
| FRD-4 | Bot protection without CAPTCHA: signed session token issued on form open, minimum time before submit, hidden honeypot field. | P1 |
| FRD-5 | Staff test mode through a preview token that bypasses limits and block lists and tags the order as a test. | P1 |
| FRD-6 | Every rejection is logged with its reason and is visible to the merchant in a blocked-attempts list. | P2 |

## 9. Requirements: offers

No offer ships in P1. Quantity offers are the first P2 item because they are the main reason merchants choose a COD form app.

| ID | Requirement | Phase |
| --- | --- | --- |
| OFF-1 | Quantity offers: tiers of quantity plus a percentage, fixed-amount or fixed-unit-price discount. Each tier has a label, optional badge and image; one tier can be preselected. | P2 |
| OFF-2 | Quantity offers target products or collections. A product belongs to at most one active offer; the admin rejects overlaps. | P2 |
| OFF-3 | Product page widget, rendered by the app embed, showing the tiers above the buttons, in three layouts. The selected tier carries into the form. | P2 |
| OFF-4 | The same tier price applies at Shopify checkout through the existing discount function, so the prepaid path matches the form. | P2 |
| OFF-5 | Order bumps: title, description, image, price. Each is either linked to a product variant (inventory and SKU) or a custom line. Options: ticked by default, quantity picker, requires shipping, taxable. | P2 |
| OFF-6 | Order bumps target all products, selected products or collections, and have a position in the form. | P2 |
| OFF-7 | Downsell on close: after N closes, a percentage or fixed discount, shown once per session on the existing exit sheet. | P2 |
| OFF-8 | Stacking: quantity offer, then downsell, then discount code, with a merchant toggle for whether discount codes combine with offers. | P2 |
| OFF-9 | Pass-through for bundle apps: line item properties and bundle pricing from Kaching, Wide Bundles and similar reach the order unchanged. | P3 |
| OFF-10 | One-click upsell after submit: product, discount, optional timer. Accepting adds the line by order edit within a configurable window (default 5 minutes). Existing confirmation and verification messages are not changed. | P3 |
| OFF-11 | Free shipping and free gift thresholds with a progress bar. | P3 |
| OFF-12 | A/B tests on offers: up to four variants with traffic weights; locked after start. | P3 |

## 10. Requirements: order creation, thank-you and abandonment

Order creation extends the existing `CodOrderCreateService` (draft order, then completion with payment pending) and the existing `POST /api/cod_orders` endpoint.

| ID | Requirement | Phase |
| --- | --- | --- |
| ORD-1 | The service accepts and applies: shipping line from the form's rate table, COD fee, offer discounts per line, custom field values, form ID. | P1 |
| ORD-2 | The server recomputes eligibility, shipping rate, fee, offers and totals at submit. Client-sent prices are never trusted. | P1 |
| ORD-3 | The total shown to the buyer equals the order total. Totals and taxes come from a server quote backed by draft order calculation. | P1 |
| ORD-4 | Idempotency: one order per form session. A repeated submit returns the first order. | P1 |
| ORD-5 | Orders carry a `codking_form` tag, the verification tag when verified, and UTM and click IDs as additional details. | P1 |
| ORD-6 | Customer is matched or created by phone and email. No placeholder email is written to the customer or the order. | P1 |
| ORD-7 | Inventory or Shopify errors return a clear buyer message and keep the form's state. | P1 |
| ORD-8 | Existing confirmation, fulfilment and COD-to-prepaid messages fire for form orders exactly as for checkout orders. | P1 |
| ORD-9 | If order creation exceeds 8 seconds, the buyer sees a processing state and the request completes in the background. | P2 |
| TY-1 | Thank-you options: Shopify order status page (default), custom URL, in-form message with order and customer variables, WhatsApp redirect with a prefilled message. | P1 |
| ABN-1 | A session with a phone or email and no order after 15 minutes becomes an abandoned cart with source `cod_form`. | P2 |
| ABN-2 | Abandoned forms feed the existing abandoned-cart SMS and WhatsApp schedules. The recovery link reopens the form prefilled, with an optional discount. | P2 |
| ABN-3 | Optional Shopify draft order for each abandoned form, tagged `codking_abandoned_form`. | P2 |
| ABN-4 | Abandoned-form event available to Klaviyo and Omnisend. | P3 |

## 11. Requirements: tracking, integrations and analytics

| ID | Requirement | Phase |
| --- | --- | --- |
| TRK-1 | Standard events on form open (initiate checkout) and on order (purchase), sent from browser and server with a shared event ID for deduplication. | P1 |
| TRK-2 | Meta Pixel and Conversions API (existing), with multiple pixels and an option to send Lead in place of Purchase. | P1 |
| TRK-3 | TikTok Pixel and Events API. | P1 |
| TRK-4 | UTM parameters and click IDs captured at form open and stored on the order (existing attribution helper). | P1 |
| TRK-5 | The existing web pixel's `cod_order_placed` event fires for form orders. | P1 |
| TRK-6 | Tracking respects the buyer's consent from Shopify's Customer Privacy API. | P1 |
| TRK-7 | Google Ads conversion and GA4. The existing Google conversion service is currently disabled in order creation and must be re-enabled and tested. | P2 |
| TRK-8 | Snapchat and Pinterest pixels; product-specific pixels. | P3 |
| INT-1 | Google Sheets: connect a Google account, pick a sheet, map columns; each form order is appended in near real time with retries. | P2 |
| INT-2 | Klaviyo and Omnisend events for order and abandoned form. | P3 |
| INT-3 | Google address autocomplete using the merchant's own API key. | P3 |
| ANL-1 | New funnel events on the existing `FormFunnelEvent` model: button view, form open, first field input, shipping selected, submit attempt, submit error, order created, form close, prepaid redirect. | P1 |
| ANL-2 | Form analytics page: funnel, conversion rate, orders, revenue, average order value. Filters: date range, country, product, device. | P1 |
| ANL-3 | Events for OTP sent and verified, offer view and accept, downsell, recovery. | P2 |
| ANL-4 | Breakdowns by UTM campaign and by offer; compare to previous period; CSV export. | P2 |
| ANL-5 | Raw events are kept 90 days; daily rollups per shop are kept indefinitely. | P1 |

## 12. Dashboard and onboarding

COD Form is a new group in the in-app Settings sidebar. The Shopify admin navigation does not change.

**Navigation today, as in the code**

- Shopify admin nav (`ui-nav-menu` in `embedded_app.html.erb`): Summary, Settings, Analytics, Plans, Help & Support.
- Settings opens the Settings hub: a searchable sidebar built from one registry file (`Pages/SettingsHub/registry.js`), with five groups: Checkout Widget, COD Workflow, Notifications, Integrations, General.

**New sidebar group: COD Form.** Proposed position is first, above Checkout Widget. Thank-you settings are a tab inside Form designer, and Offers is one row that opens a directory of cards, so the sidebar stays short.

| Sidebar item | Path | Contains | Phase |
| --- | --- | --- | --- |
| Setup | `/features/cod-form` | COD Form on/off, app embed status with a link to the theme editor, enabled countries, visibility by page, product and collection, order total limits, setup checklist, test order, usage against the order cap | P1 |
| Buttons | `/features/cod-form/buttons` | Preset, COD button label, style and placement, sticky button, Buy now rename, hide toggles | P1 |
| Form designer | `/features/cod-form/designer` | Fields, design, texts, thank-you tab, draft and publish, live preview | P1 |
| Shipping rates | `/features/cod-form/shipping` | Rate table and conditions | P1 |
| Fraud protection | `/features/cod-form/fraud` | Block lists, order limits, maximum quantity, blocked attempts | P1 |
| Offers | `/features/cod-form/offers` | Cards for quantity offers, order bumps, upsells and downsells | P2 |

**Existing screens the form uses.** These stay where they are; the form reads their settings, so nothing is configured twice.

| Existing item | Group | What changes |
| --- | --- | --- |
| OTP verification | Checkout Widget | Its on/off, channel and template settings drive the form's OTP step. A note on the screen says so. No second OTP screen. |
| Partial payments & COD | Checkout Widget | Rules apply to form orders unchanged. This screen already has a toggle labelled "COD form" (`cod_form_enabled`) that belongs to Express checkout; it must be relabelled to avoid confusion with this module. |
| Prepaid discount | Checkout Widget | Its value can be shown in the renamed Buy now label (P2). |
| Discounts | Checkout Widget | Codes are accepted by the form's discount field (P2). |
| UI customization | Checkout Widget | Express checkout only. When COD Form is on, a banner points to Form designer. |
| Limit COD | COD Workflow | The form evaluates the same rules. Postal code prefixes and ranges are added here (RUL-2). |
| COD fees | COD Workflow | One fee configuration for form and checkout. |
| Customer notifications | Notifications | Abandoned forms use the existing abandoned-cart messages (P2). |
| Integrations | Integrations | New cards: TikTok (P1), Google Sheets (P2). Meta pixel card gains multiple pixels. |
| Billing | General | Shows form order usage and any overage charges. |
| Summary (Shopify nav) | n/a | Opt-in card for shops not using the form; usage meter for shops that are. |
| Analytics (Shopify nav) | n/a | New "COD Form" tab in the existing analytics tabs. |

| ID | Requirement | Phase |
| --- | --- | --- |
| DSH-1 | Add group `cod-form` to `SETTINGS_GROUPS` and its items to `SETTINGS_ITEMS` in the registry. No item is added to the Shopify `ui-nav-menu`. | P1 |
| DSH-2 | All paths sit under `/features/cod-form`, so the existing hub wrapping, the `/settings-hub` URL rewrite and the Settings highlight work without a new prefix. Sub-pages keep their sidebar item selected through the existing longest-prefix match. | P1 |
| DSH-3 | Each item has a translation key, an icon and search keywords (for example: cod form, order form, buy button, shipping, upsell, block, fake orders) so the hub search finds it. | P1 |
| DSH-4 | The group's visibility uses the registry's `isVisible` with the per-shop module flag (NFR-12). | P1 |
| DSH-5 | The Setup screen holds the on/off switch for COD Form mode. Turning it on asks for confirmation and keeps all Express checkout settings. | P1 |
| DSH-6 | Setup checklist: enable the app embed, choose a button preset, add a shipping rate, place a test order. Completion is tracked per step. | P1 |
| DSH-7 | No existing sidebar item is hidden when COD Form is on. Screens that affect only Express checkout show a banner saying so. | P1 |
| DSH-8 | Onboarding is the same in every country. COD Form Setup is offered to every new install as a setup step, and the form stays off until the merchant turns it on. | P1 |
| DSH-9 | Summary shows the opt-in card (existing interest-card pattern) or the usage meter, as in the table above. | P1 |
| DSH-10 | Analytics gains a "COD Form" tab (ANL-2). | P1 |
| DSH-11 | Setup health check lists: embed off, no shipping rate, no enabled country, cap reached. | P1 |
| DSH-12 | New screens follow the existing screens' patterns: Polaris components, the shared save bar, and the hub's mobile drawer. | P1 |
| DSH-13 | All new admin text is translated through the existing Crowdin flow into the 18 admin locales. | P1 |
| DSH-14 | Settings changes are written to the existing settings audit log. | P1 |
| DSH-15 | New screens meet Built for Shopify requirements. | P1 |

## 13. Plans and order cap

The free plan has a monthly cap on form orders. The cap and its behaviour are data, changed in the internal admin without a deploy. Cap values themselves are a product decision and are not set in this spec.

| ID | Requirement | Phase |
| --- | --- | --- |
| CAP-1 | A form order is an order created by the COD Form, including partial payment orders that start in the form. Prepaid redirects to Shopify checkout do not count. Test orders do not count. | P1 |
| CAP-2 | Usage is counted per shop per calendar month in the shop's time zone, in a counter updated at order creation. | P1 |
| CAP-3 | The cap resolves in this order: shop override, then country-group override, then plan default. An empty value means unlimited. | P1 |
| CAP-4 | Country groups are editable lists. The first group is the launch markets: Hungary, Colombia, Serbia, Dominican Republic, Morocco, Peru, Pakistan. | P1 |
| CAP-5 | Plan defaults, country-group overrides and shop overrides are editable in the internal admin, with an audit record of who changed what. | P1 |
| CAP-6 | Behaviour at the cap is configurable globally and per shop: fall back to Shopify checkout immediately; allow a grace of N further orders, then fall back; or keep working and only flag the shop. | P1 |
| CAP-7 | In fallback, the COD button opens Shopify checkout. It is never hidden or dead. | P1 |
| CAP-8 | The merchant sees a usage meter on Home and gets a notice at 80% and at 100%, in-app and by email. | P1 |
| CAP-9 | On paid plans, orders beyond the plan's cap can be billed per extra order through the existing usage-charge service. The rate is configurable per plan; empty means not billed. | P2 |
| CAP-10 | Feature gates per plan are a config table (feature key, minimum plan), read by both the admin UI and the server. | P1 |

**Proposed gates, for product sign-off**

| Free | Paid |
| --- | --- |
| Form, buttons, shipping rates, COD fee, quantity offers, block lists and limits, one pixel, basic analytics | Order bumps, upsells, downsells, multiple forms, Google Sheets, extra pixels, risk-based OTP, RTO gating, branding removal, A/B tests |

## 14. Data model and APIs

New configuration goes into new tables. The `settings` table already has about 250 columns and must not grow for this module, beyond a single storefront-mode field. Table and endpoint names below are proposals for engineering to refine.

**New tables**

| Table | Holds |
| --- | --- |
| `cod_forms` | Per shop: name, default flag, targeting, draft config, published config, published-at. Config is JSON: fields, blocks, design, texts, thank-you. |
| `cod_button_configs` | Per shop: preset, button styles, hide toggles, visibility rules. |
| `cod_shipping_rates` | Rate name, description, price, conditions, position, active flag. |
| `cod_offers` | Type (quantity, bump, upsell, downsell), targeting, config, status, priority. |
| `cod_block_entries` | Kind (phone, email, IP), value, note, created-by. |
| `cod_form_sessions` | Session token, cart snapshot, contact captured, idempotency key, resulting order ID, abandoned-at. |
| `tracking_pixels` | Platform, pixel ID, server token, event mapping, product targeting. |
| `form_order_usages` | Shop, month, count. |
| `plan_limits` | Scope (plan, country group, shop), cap, at-cap behaviour, overage rate. |
| `feature_gates` | Feature key, minimum plan. |

**Reused as is or extended**

- `Setting`: COD fee, verification tag, OTP and messaging settings, COD rule fields. One new field for storefront mode.
- `FormFunnelEvent`: new event types (ANL-1, ANL-3).
- `AbandonedCart`: new source `cod_form`.
- `CodOrderCreateService`, `DraftOrderCalculateService`, `OrderEditService`, RTO `DecisionService`, the payment, delivery and discount functions, the cart transform, and the web pixel.

**Storefront endpoints**

| Endpoint | Purpose | Status |
| --- | --- | --- |
| `POST /api/form/session` | Issues the signed session token; returns published config, eligibility and cap state | New |
| `POST /api/form/quote` | Returns rule results, qualifying shipping rates, fee, offer pricing, taxes and total for the current cart and address | New |
| `POST /api/form/contact` | Saves phone or email to the session for abandonment | New (P2) |
| OTP send and verify | Existing pre-order OTP endpoints, called with the session token | Existing |
| `POST /api/cod_orders` | Creates the order; now requires the session token and idempotency key | Existing, hardened |
| `POST /api/form/upsell_accept` | Adds the upsell line to the created order | New (P3) |
| `POST /form_funnel/ingest` | Funnel events | Existing |

**Storefront delivery**

- Every storefront element (COD button, sticky button, form, and later the quantity-offer widget and embedded form) is created only by the app embed in the existing theme extension. No app blocks.
- The form is a separate, new storefront implementation with its own source directory, build and bundle. It does not import from, or ship inside, `notifik-svelte-app`. Express checkout stays in the Svelte app, unchanged.
- The backend is shared. The new form calls the Rails endpoints above and the existing OTP and partial payment services.
- The embed is conditional. It outputs nothing when COD Form mode is off, and includes only the config and modules for features the merchant has enabled.
- Button config needed before first paint is delivered with the page (shop metafield read by the embed). The full form config loads with the session call.

## 15. Non-functional requirements

Numeric targets are proposals; engineering should confirm or counter them in review.

| ID | Requirement | Phase |
| --- | --- | --- |
| NFR-1 | Embed output on an eligible page: at most 5 KB gzipped of script and CSS, async and non-blocking. Zero bytes of form code when COD Form mode is off. | P1 |
| NFR-2 | No layout shift from the injected button: space is reserved before the script runs. | P1 |
| NFR-3 | Form visible within 1 second of tap at the 75th percentile on a 4G mobile connection, with one network round trip (the session call) to open. | P1 |
| NFR-4 | Quote API under 400 ms at the 95th percentile. Order creation under 6 seconds at the 95th percentile. | P1 |
| NFR-5 | Any loader, session or config failure falls back to Shopify checkout. | P1 |
| NFR-6 | `POST /api/cod_orders` is public and unthrottled today. It must require a valid session token, enforce rate limits per IP, phone and shop, and accept requests only from the shop's own domains. | P1 |
| NFR-7 | The order service currently logs full draft-order variables, including name, phone and address, and posts a Slack message per order for Meta events. Personal data must be removed from logs and per-order Slack posts replaced by error-only alerts. | P1 |
| NFR-8 | Customer data requests and deletion (Shopify privacy webhooks) cover form sessions, abandoned forms and block lists. | P1 |
| NFR-9 | Works on Online Store 2.0 themes. Tested on Dawn and the ten most-used themes in the current merchant base, and on GemPages, PageFly and Zipify pages. | P1 |
| NFR-10 | Form meets WCAG 2.1 AA: keyboard operable, focus trapped in the modal, labelled inputs, sufficient contrast. | P1 |
| NFR-11 | The module passes Built for Shopify performance and design checks before general release. | P1 |
| NFR-12 | Feature flag per shop for the whole module, and a global kill switch that returns all shops to fallback. | P1 |
| NFR-13 | Error monitoring in Sentry for storefront and server; alerts on order-creation error rate above 2% over 15 minutes. | P1 |
| NFR-14 | Automated tests: unit tests for the quote and rule engine, and an end-to-end test that places a form order on a development store in CI. | P1 |
| NFR-15 | Core form bundle (script and CSS) at most 35 KB gzipped for P1 scope, loaded on intent (touch start or hover on a COD button) and cached. | P1 |
| NFR-16 | Optional steps and features (OTP step, payment option step, each offer type, each pixel) are separate chunks, fetched only when enabled for the shop. | P1 |
| NFR-17 | No heavy dependencies: no UI or utility libraries, and any framework runtime stays within the NFR-15 budget. Province and city lists are fetched per country on demand. | P1 |
| NFR-18 | Bundle sizes are checked in CI; a build over budget fails. | P1 |

## 16. Rollout and phases

Durations are product's estimate and need engineering's own numbers in review. The business goal is 300 active merchants in the launch markets by the end of 2026, so P1 needs to be generally available by mid-November.

| Phase | Contains | Estimate |
| --- | --- | --- |
| P0 | Schema, session token and endpoint hardening (NFR-6, NFR-7), feature flags, event definitions, cap config | 1 week |
| P1 | Buttons and visibility, single-page form with country address schemas, shipping rates, COD fee, OTP after form submit, partial payment option step, Buy now rename, block lists and limits, order creation changes, thank-you, prepaid hand-off, Meta and TikTok tracking, form analytics, mode selector, onboarding, order cap | 4 to 5 weeks |
| P2 | Quantity offers, order bumps, downsell, abandonment and recovery, prepaid discount, preset A, order-first OTP, risk-based OTP and RTO gating, custom fields, reorder, Google Sheets, Google tracking, overage billing | 4 to 5 weeks |
| P3 | Embedded mode, templates, multiple forms, one-click upsell, A/B tests, remaining pixels, Klaviyo and Omnisend, autocomplete, RabbitPay hook | 6 weeks |

**Rollout steps for P1**

1. Internal development stores, all presets, India and one store per launch market.
2. Private beta behind the per-shop flag: about 20 merchants, mixed between India and launch markets, for one week.
3. General release to all merchants, with no country-specific defaults: new installs see COD Form in onboarding, and existing merchants see the opt-in card.

**P1 acceptance criteria**

- A merchant on a fresh install places a test COD order through the form in under 10 minutes without support.
- The order in Shopify has the correct line items, shipping line, COD fee, tags and total, matching what the buyer saw.
- The COD button appears through the app embed alone, with no app block and no theme edit, on product page, cart page and cart drawer on the tested themes.
- With COD Form mode off, a storefront page loads no COD Form code.
- Embed and form bundles are within the NFR-1 and NFR-15 budgets.
- A renamed Buy now button shows the merchant's label after a variant change and still goes to Shopify checkout.
- With OTP enabled, the code is requested after the form is submitted, and no order exists before verification.
- With a matching partial payment rule, the payment option step appears. Partial completes through the existing partial flow with the address carried over; full COD creates the order.
- A replayed or tokenless request to the order endpoint is rejected; a double tap creates one order.
- Block list, order limit and COD rule rejections show the merchant's message.
- At the cap, the button opens Shopify checkout and the merchant has been notified.
- Purchase events reach Meta and TikTok once each, deduplicated.
- With the kill switch on, every store falls back to Shopify checkout within one page load.
- Existing Express checkout merchants see no change in behaviour.

**Success metrics after release**

| Metric | Definition |
| --- | --- |
| Active form merchants | Shops with at least one form order in the last 7 days |
| Time to first order | Install to first non-test form order |
| Form conversion | Orders divided by form opens |
| Order creation error rate | Failed submits divided by submit attempts |
| Prepaid share (guardrail) | Prepaid orders divided by all orders, for shops that switch to COD Form |
| RTO rate | Form orders versus checkout COD orders, per shop |

## 17. Open questions for engineering

Most questions were answered by the founder on 3 October 2026. Three remain for engineering.

**Resolved**

| Question | Answer | Source |
| --- | --- | --- |
| Partial payment hand-off | Same as today: the form sets the buyer identity (contact and address) on the cart and passes the cart to the existing partial payment flow. | Founder |
| Buy now rename | Use the same Buy now detection the app embed uses today (`COD_BUTTON_SELECTORS.BUY_NOW`). Shopify-branded express buttons cannot be relabelled and are left as they are. | Founder |
| Presentment currency | Yes. Draft orders are created in the buyer's currency. | Founder |
| Offer price parity | Yes. One quantity-offer definition drives both the draft-order discount and the discount function. | Founder |
| Embed coexistence | Yes, the two paths are isolated. Recommended method: the embed's Liquid branches on the shop's storefront mode, so a COD Form shop gets no Express code in the page and the reverse. One embed toggle for the merchant. | Founder; method recommended |
| Upsell by order edit | Messaging is not changed for now. Confirmation and verification messages go out as they do today. | Founder |
| Hiding theme buttons | Releasit, which holds the Built for Shopify badge, ships in-app toggles to hide Add to cart, Buy now and Checkout. EasySell has the same toggles. Proceed with BTN-9. Their help pages do not say how the hiding is done. | Competitor check |
| Cap counter | Calendar month in the shop's time zone. | Founder |
| Draft order throughput | No queue in P1. | Founder |
| Storefront stack | Recommended: Preact for the form, plain JavaScript for the embed loader and button. Preact is already a dependency in the extensions repository and is about 4 to 5 KB gzipped, which leaves most of the 35 KB budget for the form. | Recommended, for engineering to confirm |
| Code location | Recommended: a new package `storefront/cod-form/` in the `payment-customization-js` repository, with its own build that outputs to the theme extension's `assets/` folder, so files are served from Shopify's CDN. | Recommended, for engineering to confirm |
| Config delivery | Recommended: a shop metafield for mode and button config, rendered by the embed's Liquid with no extra request. This is the pattern already used for `lightweight_settings` and `partial_rule_sets`. The full form config comes with the session call. | Recommended, for engineering to confirm |

**Still open**

- [ ] **Estimates.** Engineering's own effort per phase, and whether P1 fits before mid-November with the current team.
- [ ] **Address datasets.** Province and city lists are in scope; the source and licence for the seven launch markets still need to be chosen (FRM-5).
- [ ] **Rate limiting.** Which mechanism (for example Rack::Attack on Redis) and what default limits for NFR-6.
