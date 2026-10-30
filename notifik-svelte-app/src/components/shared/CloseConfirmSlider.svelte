<script>
  import { createEventDispatcher } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import Card from "../ui/Card.svelte";
  import otpStore from "../../stores/otpStore.js";
  import {
    formatCurrency,
    mapCartToOrderSummary,
  } from "../../utils/helpers.js";
  import {
    createTranslator,
    getBrandColor,
    getBrandForeground,
  } from "../../utils/uiCustomization.js";

  const SCARCITY_ICON =
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/HourglassGreen.gif?v=1781803538";

  const dispatch = createEventDispatcher();

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore || $otpStore?.settings);

  $: brandColor = getBrandColor($settingsStore || $otpStore?.settings);
  $: brandForeground = getBrandForeground(brandColor);

  const close = () => dispatch("close");
  const confirm = () => dispatch("confirm");

  $: orderSummary = mapCartToOrderSummary($otpStore?.currentCartData, "INR");
  $: savedAmount = Math.max(
    0,
    (orderSummary?.originalTotal || 0) - (orderSummary?.total || 0),
  );
  // Split on {{amount}} so the figure keeps its own styling inside the sentence
  $: scarcityParts =
    savedAmount > 0
      ? T("close_confirm_banner_saved").split("{{amount}}")
      : [T("close_confirm_banner")];
</script>

<div
  class="exit-sheet"
  style="--exit-brand: {brandColor}; --exit-brand-fg: {brandForeground};"
>
  <div class="exit-scarcity" role="status" aria-live="polite">
    <img class="exit-scarcity-icon" src={SCARCITY_ICON} alt="" />
    <span>
      {#if savedAmount > 0}
        {scarcityParts[0]}<strong
          >{formatCurrency(savedAmount, orderSummary?.currency || "INR")}</strong
        >{scarcityParts[1] ?? ""}
      {:else}
        {scarcityParts[0]}
      {/if}
    </span>
  </div>

  <div class="exit-card-wrap">
    <Card variant="soft" padding="none" attach="bottom">
      <div class="exit-actions">
        <button type="button" class="exit-button exit-button--leave" on:click={confirm}>
          {T("close_confirm_leave")}
        </button>
        <button type="button" class="exit-button exit-button--stay" on:click={close}>
          {T("close_confirm_continue")}
        </button>
      </div>
    </Card>
  </div>
</div>

<style>
  .exit-sheet {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .exit-scarcity {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
    padding: 6px 12px;
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-medium);
    line-height: 18px;
    text-align: center;
    color: rgb(36, 128, 24);
    background: linear-gradient(
      to right,
      rgb(243, 253, 245),
      rgb(173, 243, 187)
    );
  }

  .exit-scarcity strong {
    font-weight: var(--font-weight-semibold);
  }

  .exit-scarcity-icon {
    width: 11px;
    height: 15px;
    margin-top: -2px;
    flex-shrink: 0;
    object-fit: contain;
  }

  .exit-card-wrap {
    padding: var(--space-2) var(--space-2) 0;
  }

  .exit-actions {
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding: 24px 12px calc(env(safe-area-inset-bottom, 0px) + 24px);
  }

  .exit-button {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    height: 48px;
    padding: 0 12px;
    border-radius: var(--radius-sm);
    font-family: var(--font-family-base);
    font-size: var(--font-size-sm);
    font-weight: var(--font-weight-medium);
    cursor: pointer;
    transition:
      background-color 220ms var(--ease-smooth),
      border-color 220ms var(--ease-smooth),
      color 220ms var(--ease-smooth),
      transform 150ms var(--ease-smooth);
  }

  .exit-button:active {
    transform: scale(var(--press-scale));
  }

  .exit-button--leave {
    border: 0.75px solid var(--exit-brand);
    background: var(--surface-card);
    color: var(--color-text-primary);
  }

  .exit-button--stay {
    border: 0.75px solid transparent;
    background: var(--exit-brand);
    color: var(--exit-brand-fg);
  }

  /* Emphasis follows the pointer: reaching for "exit" fills it and hollows out
     "continue", so only one button ever reads as the primary action. */
  .exit-button--leave:hover,
  .exit-button--leave:focus-visible {
    background: var(--exit-brand);
    color: var(--exit-brand-fg);
  }

  .exit-button--leave:hover ~ .exit-button--stay,
  .exit-button--leave:focus-visible ~ .exit-button--stay {
    border-color: var(--exit-brand);
    background: var(--surface-card);
    color: var(--color-text-primary);
  }

  @media (prefers-reduced-motion: reduce) {
    .exit-button {
      transition: none;
    }
    .exit-button:active {
      transform: none;
    }
  }
</style>
