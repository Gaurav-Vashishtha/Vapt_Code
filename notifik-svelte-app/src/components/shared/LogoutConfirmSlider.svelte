<script>
  import { createEventDispatcher } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import Sheet from "../ui/Sheet.svelte";
  import Card from "../ui/Card.svelte";
  import otpStore from "../../stores/otpStore.js";
  import {
    formatCurrency,
    mapCartToOrderSummary,
  } from "../../utils/helpers.js";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);

  export let open = false;
  export let loading = false;
  export let phone = "";

  const SCARCITY_ICON =
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/HourglassGreen.gif?v=1781803538";

  const dispatch = createEventDispatcher();

  const close = () => dispatch("close");
  const confirm = () => dispatch("confirm");

  $: orderSummary = mapCartToOrderSummary($otpStore?.currentCartData, "INR");
  $: savedAmount = Math.max(
    0,
    (orderSummary?.originalTotal || 0) - (orderSummary?.total || 0),
  );
</script>

<Sheet
  {open}
  title={T("logout_confirm_title")}
  closeLabel="Close"
  headerBorder={false}
  bodyPadded={false}
  dismiss={close}
>
  <div class="logout-sheet">
    <div class="logout-scarcity" role="status" aria-live="polite">
      <img class="logout-scarcity-icon" src={SCARCITY_ICON} alt="" />
      <span>
          {T("logout_confirm_message")}
      </span>
    </div>

    <div class="logout-card-wrap">
      <Card variant="soft" padding="none" attach="bottom">
        <div class="logout-actions">
          <button
            type="button"
            class="logout-button logout-button--leave"
            disabled={loading}
            on:click={confirm}
          >
            {#if loading}Logging out…{:else}Yes, log out{/if}
          </button>
          <button
            type="button"
            class="logout-button logout-button--stay"
            disabled={loading}
            on:click={close}
          >
            {T("logout_stay")}
          </button>
        </div>
      </Card>
    </div>
  </div>
</Sheet>

<style>
  .logout-sheet {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .logout-scarcity {
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

  .logout-scarcity strong {
    font-weight: var(--font-weight-semibold);
  }

  .logout-scarcity-icon {
    width: 11px;
    height: 15px;
    margin-top: -2px;
    flex-shrink: 0;
    object-fit: contain;
  }

  .logout-card-wrap {
    padding: var(--space-2) var(--space-2) 0;
  }

  .logout-actions {
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding: 24px 12px calc(env(safe-area-inset-bottom, 0px) + 24px);
  }

  .logout-button {
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

  .logout-button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .logout-button:active {
    transform: scale(var(--press-scale));
  }

  .logout-button--leave {
    border: 0.75px solid var(--color-blue);
    background: var(--surface-card);
    color: var(--color-text-primary);
  }

  .logout-button--stay {
    border: 0.75px solid transparent;
    background: var(--color-blue);
    color: #ffffff;
  }

  /* Emphasis follows the pointer: reaching for "log out" fills it and hollows
     out "stay", so only one button ever reads as the primary action. */
  .logout-button--leave:hover:not(:disabled),
  .logout-button--leave:focus-visible {
    background: var(--color-blue);
    color: #ffffff;
  }

  .logout-button--leave:hover:not(:disabled) ~ .logout-button--stay,
  .logout-button--leave:focus-visible ~ .logout-button--stay {
    border-color: var(--color-blue);
    background: var(--surface-card);
    color: var(--color-text-primary);
  }

  @media (prefers-reduced-motion: reduce) {
    .logout-button {
      transition: none;
    }
    .logout-button:active {
      transform: none;
    }
  }
</style>
