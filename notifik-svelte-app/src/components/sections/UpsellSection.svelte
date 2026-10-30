<script>
  import otpStore from "../../stores/otpStore.js";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { fetchUpsellProducts, addUpsellToCart, autoAddUpsells } from "../../services/upsellService.js";
  import { formatCurrency } from "../../utils/helpers.js";
  import { toast } from "../../utils/toast.js";
  import Card from "../ui/Card.svelte";
  import Sheet from "../ui/Sheet.svelte";
  import Spinner from "../shared/Spinner.svelte";
  import { createTranslator } from "../../utils/uiCustomization.js";

  let { showDisplay = false } = $props();

  let T = $derived(createTranslator($settingsStore));
  let config = $derived($settingsStore?.upsellConfig ?? $settingsStore?.upsell_config ?? null);
  let title = $derived(T("upsell_title"));
  let showQuantity = $derived(config?.show_quantity_selector === true || config?.showQuantitySelector === true);
  let sheetBannerColor = $derived.by(() => {
    const s = /** @type {any} */ ($otpStore?.settings || {});
    return s.promoBannerColor || s.promo_banner_color || "";
  });
  let sheetBannerTextColor = $derived.by(() => {
    const s = /** @type {any} */ ($otpStore?.settings || {});
    return s.promoTextColor || s.promo_text_color || "";
  });
  let cartReady = $derived($otpStore.isCartReady && !$otpStore.isSummaryOptimistic);
  let cartItems = $derived($otpStore.currentCartData?.items || []);

  let started = false;
  let loading = $state(true);
  let products = $state([]);
  let currency = $state("INR");
  let addingVariantId = $state(null);
  let picker = $state(null);
  let selected = $state([]);
  let quantities = $state({});

  $effect(() => {
    if (started || !config?.enabled || !cartReady) return;
    const ids = [...new Set(cartItems.map((i) => i.product_id).filter(Boolean))];
    started = true;
    if (!ids.length) {
      loading = false;
      return;
    }
    fetchUpsellProducts(ids)
      .then(async (res) => {
        products = Array.isArray(res?.products) ? res.products : [];
        currency = res?.currency || $otpStore.currentCartData?.currency || "INR";
        const added = await autoAddUpsells(res?.auto_add_variant_ids, $otpStore.currentCartData?.token);
        if (added.length) {
          products = products.filter((p) => !p.variants.some((v) => added.includes(v.id)));
        }
      })
      .catch(() => {
        products = [];
      })
      .finally(() => {
        loading = false;
      });
  });

  const money = (amount) => formatCurrency(amount, currency);
  const hasCompare = (v) => Number(v?.compare_at_price) > Number(v?.price);
  const percentOff = (v) =>
    Math.round(((Number(v.compare_at_price) - Number(v.price)) / Number(v.compare_at_price)) * 100);
  const variantLabel = (p, v) =>
    v && v.title && v.title !== "Default Title" ? `${p.title} - ${v.title}` : p.title;
  const imageOf = (p, v) => v?.image || p.image;
  const savings = (v) => (hasCompare(v) ? percentOff(v) : 0);
  const displayVariant = (p) =>
    p.variants.reduce((best, v) => (savings(v) > savings(best) ? v : best), p.variants[0]);

  const findVariant = (p, values) =>
    p.variants.find((v) => values.every((value, i) => v.options[i] === value)) || null;

  let pickerVariant = $derived(picker ? findVariant(picker, selected) : null);

  const qtyOf = (p) => (showQuantity ? quantities[p.id] || 1 : 1);
  const setQty = (p, value) => (quantities[p.id] = Math.max(1, value));

  function chipAvailable(p, optionIndex, value) {
    return p.variants.some((v) =>
      v.options.every((o, i) => (i === optionIndex ? o === value : o === selected[i])),
    );
  }

  function selectChip(optionIndex, value) {
    const next = [...selected];
    next[optionIndex] = value;
    const exact = findVariant(picker, next);
    const fallback = exact || picker.variants.find((v) => v.options[optionIndex] === value);
    if (fallback) selected = [...fallback.options];
  }

  function openPicker(p) {
    picker = p;
    selected = [...displayVariant(p).options];
  }

  async function add(p, variantId) {
    if (addingVariantId) return;
    addingVariantId = variantId;
    try {
      await addUpsellToCart(variantId, true, qtyOf(p));
      delete quantities[p.id];
      picker = null;
      toast.success(T("upsell_added_toast"));
    } catch (e) {
      toast.error(e?.message || "Could not add this item.");
    } finally {
      addingVariantId = null;
    }
  }

  function onCardButton(p) {
    if (p.variants.length > 1) openPicker(p);
    else add(p, p.variants[0].id);
  }
</script>

{#snippet stepper(p, size)}
  {@const qty = qtyOf(p)}
  <div class="cu-qty cu-qty--{size}">
    <button
      type="button"
      class="cu-qty-btn"
      aria-label="Decrease quantity"
      disabled={qty <= 1 || addingVariantId !== null}
      onclick={() => setQty(p, qty - 1)}>&minus;</button>
    <span class="cu-qty-value" aria-live="polite">{qty}</span>
    <button
      type="button"
      class="cu-qty-btn"
      aria-label="Increase quantity"
      disabled={addingVariantId !== null}
      onclick={() => setQty(p, qty + 1)}>+</button>
  </div>
{/snippet}

{#if showDisplay && config?.enabled && (loading || products.length)}
  <Card variant="elevated" padding="md" class="cu-section">
    <div class="cu-heading">{title}</div>
    <div class="cu-slider">
      {#if loading}
        {#each [0, 1] as i (i)}
          <div class="cu-card cu-card--skeleton" aria-hidden="true">
            <div class="cu-image cu-skel"></div>
            <div class="cu-details">
              <div class="cu-skel cu-skel-line"></div>
              <div class="cu-skel cu-skel-line cu-skel-line--short"></div>
              <div class="cu-skel cu-skel-line cu-skel-line--price"></div>
            </div>
          </div>
        {/each}
      {:else}
        {#each products as p (p.id)}
          {@const v = displayVariant(p)}
          <div class="cu-card">
            <button type="button" class="cu-image" onclick={() => openPicker(p)} aria-label="View {p.title}">
              {#if imageOf(p, v)}
                <img class="cu-product-img" src={imageOf(p, v)} alt={p.title} loading="lazy" />
              {/if}
            </button>
            <div class="cu-details">
              <p class="cu-title">{variantLabel(p, p.variants.length > 1 ? v : null)}</p>
              <div class="cu-price" class:cu-price--stacked={showQuantity}>
                {#if hasCompare(v)}<span class="cu-original-price">{money(v.compare_at_price)}</span>{/if}<span class="cu-current-price">{money(v.price)}</span>
                {#if hasCompare(v)}<span class="cu-discount">{percentOff(v)}% off</span>{/if}
              </div>
              <div class="cu-row">
                {#if showQuantity}
                  {@render stepper(p, "sm")}
                {/if}
                <button
                  type="button"
                  class="cu-add-btn"
                  disabled={addingVariantId !== null}
                  onclick={() => onCardButton(p)}
                >
                  {#if addingVariantId === v.id && p.variants.length === 1}
                    <Spinner size={12} />
                  {:else if p.variants.length > 1}
                    {T("upsell_options", { count: p.variants.length })}
                  {:else}
                    {T("upsell_add")}
                  {/if}
                </button>
              </div>
            </div>
          </div>
        {/each}
      {/if}
    </div>
  </Card>
{/if}

<Sheet open={picker !== null} {title} closeLabel="Close" headerBorder={false} headerBanner={true} headerBackground={sheetBannerColor} headerTextColor={sheetBannerTextColor} dismiss={() => (picker = null)}>
  {#if picker}
    <div class="uv-container">
      {#if imageOf(picker, pickerVariant)}
        <div class="uv-img-container">
          <img class="uv-img" src={imageOf(picker, pickerVariant)} alt={picker.title} />
        </div>
      {/if}
      <div class="uv-title">{variantLabel(picker, pickerVariant)}</div>
      {#if pickerVariant}
        <div class="uv-price">
          {#if hasCompare(pickerVariant)}<span class="uv-compare">{money(pickerVariant.compare_at_price)}</span>{/if}<span>{money(pickerVariant.price)}</span>
          {#if hasCompare(pickerVariant)}<span class="uv-discount">{percentOff(pickerVariant)}% off</span>{/if}
        </div>
      {/if}
      {#if picker.variants.length > 1}
        {#each picker.options as option, optionIndex (option.name)}
          <div class="uv-option">
            <div class="uv-option-name">{T("upsell_select_option", { name: option.name })}</div>
            <div class="uv-option-values">
              {#each option.values as value (value)}
                <button
                  type="button"
                  class="uv-chip"
                  class:is-selected={selected[optionIndex] === value}
                  disabled={!chipAvailable(picker, optionIndex, value)}
                  onclick={() => selectChip(optionIndex, value)}
                >
                  {value}
                </button>
              {/each}
            </div>
          </div>
        {/each}
      {/if}
      <div class="uv-cta-container">
        {#if showQuantity}
          {@render stepper(picker, "lg")}
        {/if}
        <button
          type="button"
          class="uv-add-btn"
          disabled={!pickerVariant || addingVariantId !== null}
          onclick={() => add(picker, pickerVariant.id)}
        >
          {#if addingVariantId !== null}
            {T("upsell_adding")}
          {:else}
            {T("upsell_add_to_cart")}
          {/if}
        </button>
      </div>
    </div>
  {/if}
</Sheet>

<style>
  .cu-heading {
    font-size: var(--font-size-base);
    line-height: 22px;
    font-weight: var(--font-weight-semibold);
    color: var(--color-text-primary);
    margin-bottom: var(--space-3);
  }

  .cu-slider {
    display: flex;
    gap: var(--space-2);
    overflow-x: auto;
    width: calc(100% + 32px);
    margin: -10px -16px -12px;
    padding: 10px 16px 12px;
    box-sizing: border-box;
    scrollbar-width: none;
    -ms-overflow-style: none;
  }
  .cu-slider::-webkit-scrollbar {
    display: none;
  }

  .cu-card {
    flex-shrink: 0;
    display: flex;
    gap: 10px;
    width: 252px;
    min-height: 82px;
    padding: 10px;
    box-sizing: border-box;
    background: var(--surface-card);
    border: 0.8px solid var(--Stroke---card-widget, #3173e31a);
    border-radius: 8px;
    box-shadow: 4px 4px 11px 0 #d0dbf726, -2px -2px 10px 0 #d0dbf726;
  }

  .cu-image {
    position: relative;
    flex-shrink: 0;
    width: 60px;
    height: 60px;
    padding: 0;
    border: 0;
    border-radius: var(--radius-base);
    background: var(--surface-sunken);
    overflow: hidden;
    cursor: pointer;
  }
  .cu-product-img {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: contain;
    box-sizing: border-box;
  }

  .cu-details {
    display: flex;
    flex: 1 1 0%;
    flex-direction: column;
    justify-content: space-between;
    gap: var(--space-1);
    min-width: 0;
  }
  .cu-title {
    margin: 0;
    font-size: 13px;
    line-height: 18px;
    font-weight: var(--font-weight-medium);
    color: var(--color-text-primary);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .cu-row {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 6px;
  }
  .cu-price {
    position: relative;
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    column-gap: 6px;
    min-width: 0;
  }
  .cu-original-price {
    font-size: var(--font-size-caption);
    line-height: 16px;
    color: var(--color-text-muted);
    text-decoration: line-through;
  }
  .cu-current-price {
    font-size: 13px;
    line-height: 18px;
    font-weight: var(--font-weight-semibold);
    color: var(--color-text-primary);
  }
  .cu-discount {
    position: absolute;
    top: calc(100% + 1.5px);
    left: 0;
    white-space: nowrap;
    font-size: 12px;
    line-height: 16px;
    font-weight: var(--font-weight-medium);
    color: var(--color-savings-strong);
  }

  .cu-price--stacked .cu-discount {
    position: static;
    flex-basis: 100%;
  }

  .cu-add-btn {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 74px;
    height: 26px;
    padding: 0 var(--space-2);
    border: 0.8px solid var(--color-blue);
    border-radius: var(--radius-sm);
    background: var(--surface-card);
    color: var(--color-blue);
    font-family: inherit;
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-bold);
    white-space: nowrap;
    cursor: pointer;
  }
  .cu-add-btn:disabled {
    cursor: default;
  }

  .cu-qty {
    flex-shrink: 0;
    display: inline-flex;
    align-items: stretch;
    box-sizing: border-box;
    border: 1px solid color-mix(in srgb, var(--color-blue) 20%, transparent);
    border-radius: var(--radius-sm);
    background: var(--surface-card);
    overflow: hidden;
  }
  .cu-qty--sm {
    height: 26px;
  }
  .cu-qty--lg {
    height: 48px;
    border-radius: var(--radius-base);
  }
  .cu-qty-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    padding: 0;
    border: 0;
    background: transparent;
    color: var(--color-text-primary);
    font-family: inherit;
    font-size: 15px;
    font-weight: var(--font-weight-semibold);
    line-height: 1;
    cursor: pointer;
    touch-action: manipulation;
  }
  .cu-qty--lg .cu-qty-btn {
    width: 40px;
    font-size: 20px;
  }
  .cu-qty-btn:disabled {
    color: var(--color-placeholder);
    cursor: default;
  }
  .cu-qty-value {
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 20px;
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-bold);
    color: var(--color-text-primary);
    font-variant-numeric: tabular-nums;
  }
  .cu-qty--lg .cu-qty-value {
    min-width: 28px;
    font-size: var(--font-size-base);
  }

  .cu-skel {
    border-radius: 6px;
    background: linear-gradient(90deg, #eef1f6 25%, #e2e6ee 50%, #eef1f6 75%);
    background-size: 200% 100%;
    animation: cu-skel-loading 1.5s ease-in-out infinite;
  }
  .cu-skel-line {
    height: 12px;
    width: 90%;
  }
  .cu-skel-line--short {
    width: 60%;
  }
  .cu-skel-line--price {
    width: 40%;
    height: 14px;
  }
  @keyframes cu-skel-loading {
    0% {
      background-position: 200% 0;
    }
    100% {
      background-position: -200% 0;
    }
  }

  .uv-container {
    padding: var(--space-4) var(--space-3) 0;
    background: var(--surface-card);
    border-radius: var(--radius-base);
    color: var(--color-text-primary);
  }
  .uv-img-container {
    display: flex;
    justify-content: center;
    height: 220px;
  }
  .uv-img {
    height: 100%;
    max-width: 100%;
    object-fit: contain;
    border-radius: var(--radius-base);
  }
  .uv-title {
    margin: var(--space-3) 0 var(--space-1);
    font-size: var(--font-size-base);
    line-height: 22px;
    font-weight: var(--font-weight-semibold);
  }
  .uv-price {
    display: flex;
    align-items: baseline;
    gap: var(--space-2);
    margin-bottom: var(--space-3);
    font-size: var(--font-size-sm);
    font-weight: var(--font-weight-semibold);
  }
  .uv-compare {
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-regular);
    color: var(--color-text-muted);
    text-decoration: line-through;
  }
  .uv-discount {
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-medium);
    color: var(--color-savings-strong);
  }
  .uv-option {
    margin: var(--space-3) 0;
  }
  .uv-option-name {
    margin-bottom: 6px;
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-medium);
    color: var(--color-text-secondary);
  }
  .uv-option-values {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
  }
  .uv-chip {
    padding: 6px 10px;
    border: 0.8px solid var(--color-border-strong);
    border-radius: var(--radius-sm);
    background: var(--surface-card);
    color: var(--color-text-primary);
    font-family: inherit;
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-bold);
    cursor: pointer;
  }
  .uv-chip.is-selected {
    border-color: var(--color-blue);
    color: var(--color-blue);
  }
  .uv-chip:disabled {
    cursor: not-allowed;
    color: var(--color-placeholder);
    background: var(--surface-muted);
    text-decoration: line-through;
  }
  .uv-cta-container {
    display: flex;
    gap: var(--space-2);
    position: sticky;
    bottom: 0;
    padding: var(--space-2) 0 var(--space-3);
    background: var(--surface-card);
  }
  .uv-add-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    flex: 1 1 auto;
    width: 100%;
    min-height: 48px;
    border: none;
    border-radius: var(--radius-base);
    background: var(--color-blue);
    color: #fff;
    font-family: inherit;
    font-size: var(--font-size-base);
    font-weight: var(--font-weight-semibold);
    cursor: pointer;
  }
  .uv-add-btn:disabled {
    opacity: 0.5;
  }
</style>
