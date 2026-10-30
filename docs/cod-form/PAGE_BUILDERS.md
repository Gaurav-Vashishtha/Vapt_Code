# COD Form — hooks for page builders and custom themes (BTN-10)

How to open the COD King COD Form from GemPages, PageFly, Zipify Pages, a custom section or a plain link.
Nothing here needs a theme code edit: every hook works as soon as the **COD King – COD Form** app embed
is on and COD Form mode is live.

## 1. Before you start

| Check | Why |
| --- | --- |
| Theme editor → App embeds → **COD King – COD Form** is on | The embed provides the hooks. It prints nothing when COD Form mode is off. |
| The page type is enabled on the Buttons screen | Product pages need "Product page". Landing pages made with a page builder are usually Shopify *pages* (not product pages): they need **Cart drawer** or **Quick-buy** on, because that is what switches the embed on outside product and cart pages. |
| The buyer's country is enabled | Outside the enabled countries the embed prints nothing and your button does nothing — give it a normal link (see 2.1) so it still works. |

Check in the browser console: `window.CODKing` exists → the hooks are live on this page.

The builders rename their menus between versions, and class names such as `.gp-product-button-wrapper`
or `.zpa-buy-button` below are examples: confirm them on your page with the browser inspector. What
does not change is the hook itself — the class `codking-open-form` and `window.CODKing.openForm()`.

## 2. The two hooks

### 2.1 CSS class `codking-open-form`

Any element with this class opens the form when clicked. Optional attributes:

| Attribute | Meaning |
| --- | --- |
| `data-variant-id="44111"` | Order this variant. Without it: the product selected on the product page, or the whole cart on any other page. |
| `data-quantity="2"` | Quantity for `data-variant-id` (default 1). |

```html
<!-- product page: whatever variant and quantity the buyer selected -->
<button type="button" class="codking-open-form">Order now, pay on delivery</button>

<!-- landing page: a fixed variant -->
<a class="codking-open-form" data-variant-id="44111" data-quantity="2"
   href="/cart/44111:2">Buy 2 — cash on delivery</a>

<!-- anywhere: the buyer's cart -->
<button type="button" class="codking-open-form">Checkout with COD</button>
```

Tip: on a link, keep a working `href` (a cart permalink `/cart/<variant>:<quantity>` or `/checkout`).
The form opens instead of following it; if the embed is not active on the page, the link still takes
the buyer to checkout.

### 2.2 JavaScript

```js
window.CODKing.openForm({ variantId: 44111, quantity: 2 });   // a fixed variant
window.CODKing.openForm();                                    // current product selection, or the cart
window.CODKing.openForm({ variantId: 44111, quantity: 1, properties: { Engraving: "Anna" } });
window.CODKing.close();
```

Wait for the API when your script may run first:

```js
function openCodForm(opts) {
  if (window.CODKing) return window.CODKing.openForm(opts);
  document.addEventListener("codking:ready", function () { window.CODKing.openForm(opts); }, { once: true });
}
```

Events (on `document`, details in `event.detail`):

```js
CODKing.on("codking:form:open", function (e) { /* … */ });
CODKing.on("codking:order:created", function (e) { console.log(e.detail.order); });
CODKing.on("codking:fallback", function (e) { console.log(e.detail.reason); });
```

Full list: `codking:ready`, `codking:button:render`, `codking:form:open`, `codking:form:step`,
`codking:form:close`, `codking:form:submit`, `codking:form:error`, `codking:order:created`,
`codking:handoff`, `codking:pay_online` (cancelable), `codking:fallback`.

A hook is never a dead end: if the form cannot open (order cap reached, script blocked, network
error) the buyer is sent to Shopify checkout with the same items.

## 3. GemPages

**Product page made with GemPages.** GemPages keeps a real Shopify product form (`form[action*="/cart/add"]`
with the Add to cart button), so the automatic COD button appears below the buy buttons with no setup.
If it lands in the wrong place, set a custom position on the Buttons screen: Placement → Custom selector,
and give the selector of the element the button should be appended to (for example the product form's
wrapper, `.gp-product-button-wrapper` — confirm the class in your page with the browser inspector).

**Your own button** (landing page, hero, sticky bar):

1. Add a **Button** element.
2. Open its settings → *Advanced* → **CSS class** and enter `codking-open-form`.
3. For a fixed product: set the button's link to the cart permalink `/cart/<variant id>:1`, then add a
   **Custom Code / HTML & Liquid** element instead of a Button when you need `data-variant-id`
   (GemPages buttons cannot carry custom data attributes):

```html
<button type="button" class="codking-open-form gp-button" data-variant-id="44111" data-quantity="1">
  Order now — cash on delivery
</button>
```

## 4. PageFly

**Product page made with PageFly.** PageFly's Product Details element renders a Shopify product form;
the automatic button is placed below its Add to cart / Buy now buttons. To move it, use Placement →
Custom selector on the Buttons screen.

**Your own button:**

1. Add a **Button** element.
2. *General* tab → **Attributes** → *Class* → `codking-open-form`.
3. Same place → **Custom attributes** (PageFly supports them): `data-variant-id` = the variant id,
   `data-quantity` = `1`.
4. Set *Action* → *Open link* to `/checkout` as the safety net.

Or use an **HTML/Liquid** element with the snippet of section 2.1.

## 5. Zipify Pages

Zipify Pages blocks (Buy Box, Buy Button) submit to Shopify's cart, and the page is a Shopify *page*
or product template with its own buy button markup.

- **Buy Box on a product template:** when the block contains a standard `form[action*="/cart/add"]`,
  the automatic button appears below it. If it does not, add your own button (next point).
- **Your own button:** add a **Custom HTML / Liquid** block:

```html
<button type="button" class="codking-open-form zpa-button" data-variant-id="44111">
  Pay on delivery
</button>
```

- **Make the Zipify Buy button itself open the form:** give the button element the extra class
  `codking-open-form` in the block's *Custom class* field and set its product/variant; where the
  block offers no custom class, add this once in a Custom HTML block (replace the selector):

```html
<script>
  document.addEventListener("click", function (e) {
    var b = e.target.closest(".zpa-buy-button");   // the Zipify button's class on your page
    if (!b || !window.CODKing) return;             // not active → the normal Zipify action runs
    e.preventDefault(); e.stopPropagation();
    window.CODKing.openForm({ variantId: 44111, quantity: 1 });
  }, true);
</script>
```

## 6. Finding a variant id

Product page URL with the variant selected: `…/products/widget?variant=44111` → `44111`.
Or Shopify admin → Products → the product → the variant → the number at the end of the URL.

## 7. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `window.CODKing` is undefined | The embed printed nothing: COD Form mode is off, the app embed is off, the country is not enabled, or the page type is not enabled (section 1). In "test only" mode add `?codk_preview=<token>` from the Setup screen. |
| The automatic button is missing on a builder's product page | The page has no `form[action*="/cart/add"]` with a `[name="add"]` button, or the product is excluded by a visibility / COD rule. Use Placement → Custom selector, or your own `.codking-open-form` button. |
| Click goes to Shopify checkout | The form could not open (cap reached, bundle cart, subscription selected, script failure). Listen for `codking:fallback` to see `detail.reason`. |
| The wrong variant is ordered | Your button has no `data-variant-id` and the page's product form holds another variant. Add the attribute. |
| Two COD buttons | The automatic button and your own. Turn "Product page" off on the Buttons screen for that product, or remove your button. |
| The builder's own Buy now opens Express instead | The older "COD King OTP Block" embed is still on; turn it off in the theme editor if you no longer use Express checkout. |

## 8. For theme developers

- Automatic placement: the embed looks for the first product form that has `[name="add"]` (preferring
  the form whose `[name="id"]` holds a variant of the page's product), takes the closest common
  container of that button and `.shopify-payment-button`, and inserts `<div class="codkf-slot">`
  below (or above) it. The button is `<button class="codkf-btn codking-open-form">` in the light DOM,
  so it inherits the theme font.
- The selection is read at click time: `[name="id"]`, `[name="quantity"]` (also when it is linked by
  the `form` attribute), `[name^="properties["]`, `[name="selling_plan"]` of that form.
- All classes are prefixed `codkf-`; `html.codkf-on` is present while the embed is active on the
  page, `html.codkf-ok` while the current product selection is eligible for COD.
- Style overrides belong in the theme's custom CSS, for example `.codkf-slot{margin-top:16px}`.
