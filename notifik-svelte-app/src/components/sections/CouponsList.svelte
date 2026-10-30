<script>
  import otpStore from "../../stores/otpStore.js";
  import { settingsStore } from "../../stores/settingsStore.js";
  import Card from "../ui/Card.svelte";
  import Sheet from "../ui/Sheet.svelte";
  import Spinner from "../shared/Spinner.svelte";
  import CouponInputRow from "../shared/CouponInputRow.svelte";
  import {
    evaluateCoupon,
    isCouponExcluded,
    couponSavingsLabel,
    couponSavings,
    appliedSavings,
    formatSavings,
    savingsAmount,
    formatMoney,
    couponDescription,
    couponTerms,
  } from "../../utils/couponEligibility.js";
  import {
    applyCouponCode,
    removeCouponCode,
    isCodeApplied,
    reconcileExcludedCoupons,
  } from "../../services/couponCart.js";
  import { toast } from "../../utils/toast.js";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  let T = $derived(createTranslator($settingsStore));

  const DISCOUNT_ICON =
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/discount_icon-ezgif.com-resize_1.gif?v=1784542496";

  let otpState = $derived($otpStore);
  let cart = $derived(otpState.currentCartData || {});
  let settings = $derived(otpState.settings || {});
  let sheetBannerColor = $derived.by(() => {
    const s = /** @type {any} */ (settings);
    return s.promoBannerColor || s.promo_banner_color || "";
  });
  // Same text colour as the promo banner, so a light brand colour stays readable.
  let sheetBannerTextColor = $derived.by(() => {
    const s = /** @type {any} */ (otpState?.settings || {});
    return s.promoTextColor || s.promo_text_color || "";
  });
  // A coupon whose exception product is in the cart is filtered out entirely
  // (not shown as locked). If it was already applied, the silent reconcile below
  // strips it from the cart during load.
  let coupons = $derived(
    (Array.isArray(settings.activeDiscounts) ? settings.activeDiscounts : []).filter(
      (coupon) => !isCouponExcluded(coupon, cart),
    ),
  );

  // Re-evaluated whenever the cart or coupon list changes.
  let evaluated = $derived(
    coupons.map((coupon) => ({
      coupon,
      result: evaluateCoupon(coupon, cart),
      applied: coupon.code ? isCodeApplied(coupon.code) : false,
    })),
  );

  let appliedEntry = $derived(evaluated.find((e) => e.applied) || null);
  // Applied coupons STAY in the list (in their original slot) so the list is
  // consistent across apply/remove — the per-card button toggles instead.
  let applicable = $derived(evaluated.filter((e) => e.result.applicable));
  let locked = $derived(evaluated.filter((e) => !e.result.applicable));

  // Best not-yet-applied coupon = highest estimated saving.
  let best = $derived(
    [...applicable]
      .filter((e) => !e.applied)
      .sort(
        (a, b) =>
          (couponSavings(b.coupon, cart) || 0) - (couponSavings(a.coupon, cart) || 0),
      )[0] || null,
  );

  // Discounts already on the cart that aren't one of our configured coupons:
  // codes the shopper applied before opening the widget (or typed here but not
  // in the list) and Shopify automatic discounts. Auto discounts get an "Auto"
  // prefix and no remove button; codes can be removed.
  let cartDiscounts = $derived.by(() => {
    const appliedCodes = new Set(
      (cart.discount_codes || [])
        .filter((dc) => dc && dc.applicable !== false)
        .map((dc) => String(dc.code || "").trim().toLowerCase())
        .filter(Boolean),
    );
    const map = new Map();
    const add = (title, type, cents) => {
      const label = String(title || "").trim();
      if (!label) return;
      const isCode =
        type === "discount_code" || appliedCodes.has(label.toLowerCase());
      const isAuto = !isCode;
      const key = `${isAuto ? "auto" : "code"}:${label.toLowerCase()}`;
      const prev = map.get(key) || { label, isAuto, amount: 0 };
      prev.amount += (Number(cents) || 0) / 100;
      map.set(key, prev);
    };
    for (const app of cart.cart_level_discount_applications || []) {
      add(app.title, app.type, app.total_allocated_amount);
    }
    for (const item of cart.items || []) {
      for (const alloc of item.line_level_discount_allocations || []) {
        add(
          alloc?.discount_application?.title,
          alloc?.discount_application?.type,
          alloc.amount,
        );
      }
    }
    return [...map.values()].filter((d) => d.amount > 0);
  });

  let configuredLabels = $derived(
    new Set(
      coupons
        .flatMap((c) => [c.code, c.headline, c.title])
        .map((v) => String(v || "").trim().toLowerCase())
        .filter(Boolean),
    ),
  );

  let externalDiscounts = $derived(
    cartDiscounts.filter((d) => !configuredLabels.has(d.label.toLowerCase())),
  );

  // Inline card falls back to an external applied discount when no configured
  // coupon is applied/available, so the applied state is always visible.
  let externalApplied = $derived(externalDiscounts[0] || null);

  // The sheet lists configured coupons + any external ones.
  let couponCount = $derived(coupons.length + externalDiscounts.length);

  let sheetOpen = $state(false);
  let openTerms = $state({});
  let busyId = $state(null);
  let codeInput = $state("");
  let inputBusy = $state(false);
  let message = $state("");
  let messageOk = $state(false);
  let msgTimer = null;

  // Reactive safety net: if the cart changes while the widget is open and an
  // applied coupon's exception product appears, strip it silently (the primary
  // pass runs during cart hydration). No toast — invisible to the user.
  $effect(() => {
    void settings.activeDiscounts;
    void cart;
    reconcileExcludedCoupons();
  });

  // Toast-like feedback: show a message, then auto-dismiss so it stays lively.
  function flash(text, ok) {
    const str = String(text || "").trim();
    if (!str) {
      message = "";
      if (msgTimer) clearTimeout(msgTimer);
      return;
    }
    (ok ? toast.success(str) : toast.error(str)).then((shown) => {
      if (shown) return;
      message = str;
      messageOk = ok;
      if (msgTimer) clearTimeout(msgTimer);
      msgTimer = setTimeout(() => {
        message = "";
      }, 3000);
    });
  }

  function toggleTerms(id) {
    openTerms = { ...openTerms, [id]: !openTerms[id] };
  }

  function savedAmount(coupon) {
    // Use the real applied discount from the cart (e.g. ₹75), not a re-estimate.
    const s = appliedSavings(coupon, cart);
    return s > 0 ? formatMoney(s, cart) : "";
  }

  async function apply(coupon) {
    if (busyId) return;
    busyId = coupon.id;
    try {
      const res = await applyCouponCode(coupon.code);
      if (res.success) {
        flash("", true);
        sheetOpen = false;
      } else {
        flash(res.message || "Could not apply coupon.", false);
      }
    } finally {
      busyId = null;
    }
  }

  async function remove(coupon) {
    if (busyId) return;
    busyId = coupon.id;
    try {
      const res = await removeCouponCode(coupon.code);
      if (res && res.success === false) {
        flash(res.message || "Could not remove coupon.", false);
      } else {
        flash("Coupon removed", true);
      }
    } finally {
      busyId = null;
    }
  }

  // Remove an external code discount (auto discounts can't be removed).
  async function removeExternal(d) {
    if (busyId || !d || d.isAuto) return;
    busyId = `ext:${d.label}`;
    try {
      const res = await removeCouponCode(d.label);
      if (res && res.success === false) {
        flash(res.message || "Could not remove coupon.", false);
      } else {
        flash("Coupon removed", true);
      }
    } finally {
      busyId = null;
    }
  }

  async function applyTyped() {
    const code = codeInput.trim();
    if (!code || inputBusy) return;
    inputBusy = true;
    try {
      const res = await applyCouponCode(code);
      if (res.success) {
        codeInput = "";
        flash("", true);
        sheetOpen = false;
      } else {
        flash(res.message || "Could not apply coupon.", false);
      }
    } finally {
      inputBusy = false;
    }
  }
</script>

{#if coupons.length > 0 || externalDiscounts.length > 0}
  <!-- Inline compact card: primary coupon (applied or best) + view-more link -->
  <div class="cpn-inline ck-shimmer">
    {#if appliedEntry}
      <!-- A configured coupon is applied: show it as applied with remove/auto. -->
      <div class="cpn-inline-row">
        <img class="cpn-badge-img" src={DISCOUNT_ICON} alt="" />
        <span class="cpn-inline-code">{appliedEntry.coupon.code || appliedEntry.coupon.headline}</span>
        <span class="cpn-save-pill">
          {#if savedAmount(appliedEntry.coupon)}
            {T("coupon_saved")} <span class="cpn-save-amount">{savedAmount(appliedEntry.coupon)}</span>
          {:else}
            Applied
          {/if}
        </span>
          <button
            type="button"
            class="cpn-apply-link"
            disabled={busyId === appliedEntry.coupon.id}
            onclick={() => remove(appliedEntry.coupon)}
          >
            {#if busyId === appliedEntry.coupon.id}<Spinner size={14} />{:else}Remove{/if}
          </button>
      </div>
    {:else if externalApplied}
      <!-- A third-party discount is on the cart (applied outside our list):
           show it as applied — Remove for codes, AUTO badge for automatic —
           in the card itself, taking priority over any best-coupon suggestion. -->
      <div class="cpn-inline-row">
        <img class="cpn-badge-img" src={DISCOUNT_ICON} alt="" />
        <span class="cpn-inline-code">
          {externalApplied.isAuto ? `Auto ${externalApplied.label}` : externalApplied.label}
        </span>
        <span class="cpn-save-pill">
          {T("coupon_saved")} <span class="cpn-save-amount">{formatMoney(externalApplied.amount, cart)}</span>
        </span>
        {#if externalApplied.isAuto}
        {:else}
          <button
            type="button"
            class="cpn-apply-link"
            disabled={busyId === `ext:${externalApplied.label}`}
            onclick={() => removeExternal(externalApplied)}
          >
            {#if busyId === `ext:${externalApplied.label}`}<Spinner size={14} />{:else}Remove{/if}
          </button>
        {/if}
      </div>
    {:else if best}
      <!-- Nothing applied yet: suggest the best available coupon. -->
      <div class="cpn-inline-row">
        <img class="cpn-badge-img" src={DISCOUNT_ICON} alt="" />
        <span class="cpn-inline-code">{best.coupon.code || best.coupon.headline}</span>
        <span class="cpn-save-pill">
          {#if savingsAmount(best.coupon, cart)}
            Save <span class="cpn-save-amount">{savingsAmount(best.coupon, cart)}</span>
          {:else}
            {formatSavings(best.coupon, cart)}
          {/if}
        </span>
        <button
          type="button"
          class="cpn-apply-link"
          disabled={busyId === best.coupon.id}
          onclick={() => apply(best.coupon)}
        >
          {#if busyId === best.coupon.id}<Spinner size={14} />{:else}Apply{/if}
        </button>
      </div>
    {/if}

    <button type="button" class="cpn-viewmore" onclick={() => (sheetOpen = true)}>
      {#if couponCount > 0}
        View ({couponCount}) coupon{couponCount > 1 ? "s" : ""}
      {:else}
        {T("coupon_have_code")}
      {/if}
    </button>
  </div>

  <Sheet
    open={sheetOpen}
    title={T("coupon_sheet_title")}
    closeLabel="Close coupons"
    headerBorder={false}
    headerBanner={true}
    headerBackground={sheetBannerColor}
    headerTextColor={sheetBannerTextColor}
    dismiss={() => (sheetOpen = false)}
  >
    <Card variant="flat" padding="sm" attach="bottom">
      <div class="cpn-sheet">
      <CouponInputRow
        bind:value={codeInput}
        placeholder={T("coupon_placeholder")}
        busy={inputBusy}
        apply={applyTyped}
      />

      {#if message}
        <p class="cpn-msg" class:cpn-msg-ok={messageOk} class:cpn-msg-err={!messageOk}>
          {message}
        </p>
      {/if}

      {#if externalDiscounts.length > 0 || applicable.length > 0}
        <p class="cpn-section-title">{T("coupon_applicable")}</p>

        {#each externalDiscounts as d (`${d.isAuto ? "auto" : "code"}:${d.label}`)}
          <Card variant="soft" padding="snug" stack>
            <div class="cpn-card-head">
              <img class="cpn-badge-img" src={DISCOUNT_ICON} alt="" />
              <span class="cpn-card-code">
                {d.isAuto ? `Auto ${d.label}` : d.label}
              </span>
              {#if d.isAuto}
              {:else}
                <button
                  type="button"
                  class="cpn-action cpn-action-applied"
                  disabled={busyId === `ext:${d.label}`}
                  onclick={() => removeExternal(d)}
                  title={T("coupon_tap_remove")}
                >
                  {#if busyId === `ext:${d.label}`}<Spinner size={14} color="#6b7280" />{:else}Applied{/if}
                </button>
              {/if}
            </div>
            <div class="cpn-benefit">{T("coupon_saved")} {formatMoney(d.amount, cart)}</div>
          </Card>
        {/each}

        {#each applicable as { coupon, applied } (coupon.id)}
          <Card variant="soft" padding="snug" stack>
            <div class="cpn-card-head">
              <img class="cpn-badge-img" src={DISCOUNT_ICON} alt="" />
              <span class="cpn-card-code">{coupon.code || coupon.headline}</span>
              {#if coupon.method === "automatic"}
              {:else if applied}
                <button
                  type="button"
                  class="cpn-action cpn-action-applied"
                  disabled={busyId === coupon.id}
                  onclick={() => remove(coupon)}
                  title={T("coupon_tap_remove")}
                >
                  {#if busyId === coupon.id}<Spinner size={14} color="#6b7280" />{:else}Applied{/if}
                </button>
              {:else}
                <button
                  type="button"
                  class="cpn-action cpn-action-apply"
                  disabled={busyId === coupon.id}
                  onclick={() => apply(coupon)}
                >
                  {#if busyId === coupon.id}<Spinner size={14} color="var(--color-blue)" />{:else}Apply{/if}
                </button>
              {/if}
            </div>
            {#if couponSavings(coupon, cart) || couponSavingsLabel(coupon, cart)}
              <div class="cpn-benefit">
                {couponSavings(coupon, cart)
                  ? `Apply coupon and save ${formatMoney(couponSavings(coupon, cart), cart)}`
                  : couponSavingsLabel(coupon, cart)}
              </div>
            {/if}
            <p class="cpn-desc">{couponDescription(coupon, cart)}</p>
            <button class="cpn-terms-toggle" type="button" onclick={() => toggleTerms(coupon.id)}>
              {openTerms[coupon.id] ? "Hide terms" : "Terms & conditions"}
            </button>
            {#if openTerms[coupon.id]}
              <ul class="cpn-terms">
                {#each couponTerms(coupon, cart) as term}
                  <li>{term}</li>
                {/each}
              </ul>
            {/if}
          </Card>
        {/each}
      {/if}

      {#if locked.length > 0}
        <p class="cpn-section-title">{T("coupon_unlock")}</p>
        {#each locked as { coupon, result } (coupon.id)}
          <Card variant="sunken" padding="snug" stack>
            <div class="cpn-card-head">
              <img class="cpn-badge-img cpn-badge-img-dim" src={DISCOUNT_ICON} alt="" />
              <span class="cpn-card-code cpn-dim">{coupon.code || coupon.headline}</span>
              <span class="cpn-action cpn-action-locked">{T("coupon_apply")}</span>
            </div>
            {#if result.reason || result.unlockText}
              <p class="cpn-reason">{result.reason || result.unlockText}</p>
            {/if}
            <p class="cpn-desc">{couponDescription(coupon, cart)}</p>
            <button class="cpn-terms-toggle" type="button" onclick={() => toggleTerms(coupon.id)}>
              {openTerms[coupon.id] ? "Hide terms" : "Terms & conditions"}
            </button>
            {#if openTerms[coupon.id]}
              <ul class="cpn-terms">
                {#each couponTerms(coupon, cart) as term}
                  <li>{term}</li>
                {/each}
              </ul>
            {/if}
          </Card>
        {/each}
      {/if}

      {#if externalDiscounts.length === 0 && applicable.length === 0 && locked.length === 0}
          <p class="cpn-empty">{T("coupon_none")}</p>
        {/if}
      </div>
    </Card>
  </Sheet>
{/if}

<style>
  /* ---- inline compact card ---- */
  .cpn-inline {
    font-family: var(--font-family-base);
    padding: 0;
  }
  .cpn-inline.ck-shimmer {
    margin: -12px;
    padding: 12px;
    border-radius: var(--radius-md);
  }
  .cpn-inline-row {
    display: flex;
    align-items: center;
    gap: 4px;
    border-radius: var(--radius-base);
    padding: 2px;
  }
  .cpn-inline-code {
    font-size: var(--font-size-sm);
    font-weight: 500;
    color: var(--color-text-primary);
  }
  .cpn-save-pill {
    display: flex;
    align-items: center;
    gap: 4px;
    background: var(--color-savings-badge);
    color: #fff;
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-regular);
    line-height: 12px;
    padding: 4px 5px;
    border-radius: var(--radius-sm);
    text-align: left;
    white-space: nowrap;
  }

  .cpn-save-amount {
    font-weight: var(--font-weight-bold);
  }
  .cpn-apply-link {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 50px;
    margin-left: auto;
    background: none;
    border: none;
    color: var(--color-blue);
    font-size: var(--font-size-sm);
    font-weight: 600;
    cursor: pointer;
  }
  .cpn-apply-link:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .cpn-viewmore {
    background: none;
    border: none;
    padding: 0;
    color: var(--color-blue);
    font-size: var(--font-size-xs);
    font-weight: 500;
    cursor: pointer;
  }

  .cpn-badge-img {
    width: 20px;
    height: 20px;
    flex: 0 0 20px;
    object-fit: contain;
    display: inline-block;
  }
  .cpn-badge-img-dim {
    opacity: 0.45;
    filter: grayscale(1);
  }

  /* ---- sheet content ---- */
  .cpn-sheet {
    display: flex;
    flex-direction: column;
    gap: 12px;
    font-family: var(--font-family-base);
    padding: 4px 4px 8px;
  }
  .cpn-section-title {
    font-size: var(--font-size-sm);
    line-height: 18px;
    font-weight: var(--font-weight-semibold);
    color: var(--color-text-primary);
    margin: 4px 0 -2px;
  }

  .cpn-card-head {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .cpn-card-code {
    font-size: var(--font-size-sm);
    font-weight: var(--font-weight-semibold);
    text-transform: uppercase;
    color: var(--color-text-primary);
  }
  .cpn-dim {
    color: var(--color-text-muted);
  }
  .cpn-auto {
    margin-left: auto;
    font-size: var(--font-size-caption);
    font-weight: 600;
    color: var(--color-savings-strong);
  }

  .cpn-action {
    margin-left: auto;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 52px;
    background: none;
    border: none;
    padding: 0;
    font-size: var(--font-size-sm);
    font-weight: 600;
    cursor: pointer;
  }
  .cpn-action-apply {
    color: var(--color-blue);
  }
  .cpn-action-applied {
    color: #acacacab;
  }
  .cpn-action-locked {
    color:  #acacacab;
    cursor: default;
  }
  .cpn-action:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .cpn-benefit {
    display: flex;
    align-items: center;
    gap: 5px;
    flex-shrink: 0;
    width: fit-content;
    border: 0.2px solid var(--color-savings-deep);
    border-radius: var(--radius-sm);
    background: linear-gradient(
      92deg,
      rgba(227, 250, 240, 0.25) -25.78%,
      rgba(194, 244, 199, 0.25) 104.79%,
      rgba(227, 250, 240, 0.25) 119.91%,
      rgba(227, 250, 240, 0) 132.16%,
      rgba(187, 255, 206, 0.25) 0
    );
    color: #639252;
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-semibold);
    padding: 2px 15px 2px 5px;
  }
  .cpn-desc {
    margin: 0;
    font-size: var(--font-size-xs);
    color: var(--color-text-muted);
  }
  .cpn-reason {
    margin: 0;
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-medium);
    color: #df0000;
  }
  .cpn-terms-toggle {
    margin-top: 0;
    background: none;
    border: none;
    padding: 0;
    font-size: var(--font-size-caption);
    color: var(--color-text-muted);
    text-decoration: underline;
    cursor: pointer;
    text-align: left !important;
  }
  .cpn-terms {
    margin: 5px 0 0;
    color: var(--color-text-muted);
    font-size: var(--font-size-caption);
    line-height: 1.5;
  }
  .cpn-empty {
    font-size: var(--font-size-xs);
    color: var(--color-text-muted);
    text-align: center;
    padding: 14px;
  }
  .cpn-msg {
    font-size: var(--font-size-caption);
    margin: 8px 2px 0;
  }
  .cpn-msg-ok {
    color: var(--color-savings-strong);
  }
  .cpn-msg-err {
    color: var(--color-error);
  }
</style>
