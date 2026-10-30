<script>
  import Spinner from "./Spinner.svelte";

  const DISCOUNT_ICON =
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/discount_icon-ezgif.com-resize_1.gif?v=1784542496";

  let {
    value = $bindable(""),
    placeholder = "Enter coupon code",
    busy = false,
    applyLabel = "Apply",
    change = () => {},
    apply = () => {},
  } = $props();

  let canApply = $derived(!busy && String(value ?? "").trim().length > 0);

  let inputEl;

  export function focus() {
    inputEl?.focus();
  }
</script>

<div class="cpn-input-row">
  <div class="cpn-input-box">
    <img class="cpn-badge-img-sm" src={DISCOUNT_ICON} alt="" />
    <input
      type="text"
      class="cpn-input"
      bind:this={inputEl}
      {placeholder}
      bind:value
      disabled={busy}
      oninput={() => change()}
      onkeydown={(e) => e.key === "Enter" && apply()}
    />
  </div>
  <button
    type="button"
    class="cpn-input-apply"
    onclick={() => apply()}
  >
    {#if busy}<Spinner size={14} />{:else}{applyLabel}{/if}
  </button>
</div>

<style>
  .cpn-input-row {
    display: flex;
    align-items: center;
    width: 100%;
    gap: 8px;
  }
  .cpn-input-box {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 10px;
    height: 34px;
    padding: 0 12px;
    box-sizing: border-box;
    border: 1px solid color-mix(in srgb, var(--color-blue) 20%, transparent);
    border-radius: var(--radius-base);
  }
  .cpn-badge-img-sm {
    width: 18px;
    height: 18px;
    flex: 0 0 18px;
    object-fit: contain;
    display: inline-block;
  }
  .cpn-input {
    flex: 1;
    min-width: 0;
    border: none;
    outline: none;
    font-family: var(--font-family-base);
    font-size: 12px !important;
    background: transparent;
    color: var(--color-text-primary);
  }
  .cpn-input:focus,
  .cpn-input:focus-visible {
    border: none !important;
    outline: none !important;
    box-shadow: none !important;
  }
  .cpn-input-box:focus-within {
    border-color: color-mix(in srgb, var(--color-blue) 45%, transparent);
  }
  .cpn-input::placeholder {
    color: var(--color-text-muted);
  }
  .cpn-input-apply {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    min-width: 44px;
    padding-right: 4px;
    background: none;
    border: none;
    color: var(--color-blue);
    font-size: var(--font-size-sm);
    font-weight: var(--font-weight-semibold);
    cursor: pointer;
    white-space: nowrap;
  }
  .cpn-input-apply:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
