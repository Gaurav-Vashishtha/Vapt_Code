# WS4 snippet — payment customization function: "COD only through the form" and postal prefixes / ranges

**File:** `payment-customization-js/extensions/cod-king-payment-customizaton-js/src/index.js`
**Owner:** the extension owner. Not applied in this release (ARCHITECTURE.md I.6, H.8; product decision Q7).
It goes out with the next extension deploy.
**Depends on:** WS6's change in `ShopifyServices::PaymentCustomizationService`, which adds the key
`hideCodAtCheckout` (boolean) to the function configuration.

Line numbers refer to the file as it is in the mirror.

## 1. PRE-3 — hide COD at Shopify checkout

Add `hideCodAtCheckout: boolean,` to the JSDoc type of `configuration` (near line 53).

Insert **after** the `cod_only` block (after its closing `}` near line 99, before
`let hidePaymentMethodCondition = false;`):

```js
  // === COD ONLY THROUGH THE FORM (COD Form, PRE-3) ===
  // The merchant wants cash on delivery to be available only through the COD Form.
  // Hide the configured COD method(s) at Shopify checkout. Checkouts that the form itself hands
  // off with _codkCheckoutMode = "cod_only" returned above and are not affected.
  if (configuration.hideCodAtCheckout === true || configuration.hideCodAtCheckout === "true") {
    const codNames = configuration.paymentMethodName
      .split(",")
      .map((s) => s.toLowerCase().trim())
      .filter(Boolean);
    const cod = input.paymentMethods.filter((pm) =>
      codNames.some((n) => (pm.name + "").toLowerCase().trim().includes(n))
    );
    // Never hide every payment method.
    if (cod.length > 0 && cod.length < input.paymentMethods.length) {
      return { operations: cod.map((pm) => ({ hide: { paymentMethodId: pm.id } })) };
    }
    return NO_CHANGES;
  }
```

Notes for the owner:

- It sits after the `lockPaidFeature` return, so on a locked (Free) shop the key has no effect at
  checkout — the same as every other rule of this function. If product wants PRE-3 to work on Free,
  move the block above the `lockPaidFeature` check.
- Partial-payment hand-offs that are **not** `cod_only` (the partial product in the cart, paid
  online at checkout) do not need the COD method, so hiding it there is correct.
- A draft order created by the form never passes through this function.

## 2. Postal prefixes and ranges (RUL-2, same syntax as `CodForm::Engine::PostalMatcher`, E.2)

Add this helper at module level (above `export function run`):

```js
// Twin of CodForm::Engine::PostalMatcher (cod-confirm/app/services/cod_form/engine/postal_matcher.rb).
// Entry syntax: "4000*" prefix; "1000-1999" range (both sides all digits and the same length);
// anything else exact. Comparisons ignore case, spaces and hyphens.
const normalizePostal = (s) => (s + "").toUpperCase().replace(/[\s-]/g, "");

function postalMatches(code, list) {
  const c = normalizePostal(code);
  if (!c) return false;
  return (list + "")
    .split(/[,;\n]/)
    .map((s) => s.trim())
    .filter(Boolean)
    .some((entry) => {
      if (entry.endsWith("*")) return c.startsWith(normalizePostal(entry.slice(0, -1)));
      const dash = entry.indexOf("-");
      if (dash > 0) {
        const from = entry.slice(0, dash).trim();
        const to = entry.slice(dash + 1).trim();
        if (/^\d+$/.test(from) && /^\d+$/.test(to) && from.length === to.length) {
          return /^\d+$/.test(c) && Number(c) >= Number(from) && Number(c) <= Number(to);
        }
      }
      return c === normalizePostal(entry);
    });
}
```

Then replace the two exact comparisons.

Show-zip logic (near line 285) — replace

```js
      if (configuration.selectedZips.split(',').map(str => str.trim()).includes(input.cart.deliveryGroups[i].deliveryAddress?.zip+'')){
```

with

```js
      if (postalMatches(input.cart.deliveryGroups[i].deliveryAddress?.zip, configuration.selectedZips)){
```

Hide-zip logic (near line 304) — replace

```js
       if (configuration.excludedZips.split(',').map(str => str.trim()).includes(input.cart.deliveryGroups[i].deliveryAddress?.zip+'')){
```

with

```js
       if (postalMatches(input.cart.deliveryGroups[i].deliveryAddress?.zip, configuration.excludedZips)){
```

Behaviour change to announce: comparisons become case-insensitive and ignore spaces and hyphens
("sw1a 1aa" matches "SW1A1AA"). An entry such as `00-950` (Polish format: sides of different length)
or `10101-1234` stays an exact code. A missing zip never matches, as today (`"undefined"` no longer
needs to be relied on).

## 3. Tests to add in `src/index.test.js`

- `hideCodAtCheckout: true` with methods `["Cash on Delivery (COD)", "Shopify Payments"]` → one hide
  operation for the COD method; with only the COD method → no operation.
- `hideCodAtCheckout: true` and cart attribute `_codkCheckoutMode = "cod_only"` → the existing
  cod_only result (COD kept).
- `selectedZips: "110001, 4000*, 560001-560100"`: `110001`, `400012`, `560050` keep COD; `560101`,
  `110002` hide it. `excludedZips: "4000*"`: `400012` hides COD.
- `selectedZips: "00-950"`: `00-950` and `00950` keep COD; `00500` hides it.

## 4. Release steps

`npm test` in the extension folder, `shopify app deploy`, then remove the "has no effect at checkout
yet" note next to the toggle on the Setup screen and the postal help text of H.8.
