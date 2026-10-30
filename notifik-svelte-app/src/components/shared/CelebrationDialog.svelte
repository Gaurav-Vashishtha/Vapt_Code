<script>
  import { onDestroy, tick } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { loadConfetti } from "../../utils/confettiLoader.js";
  import otpStore from "../../stores/otpStore.js";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  let T = $derived(createTranslator($settingsStore));

  const DISCOUNT_ICON =
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/discount_icon-ezgif.com-resize_1.gif?v=1784542496";

  let cart = $derived($otpStore?.currentCartData);
  let isCartReady = $derived($otpStore?.isCartReady);
  let currency = $derived(cart?.currency || "INR");

  let celebration = $state(null);
  let canvasEl = $state(null);

  let prevKeys = new Set();
  let armed = false;
  let dismissTimer = 0;
  let confettiInstance = null;

  function discountList(source) {
    if (!source) return [];
    const map = new Map();
    const add = (title, type, cents) => {
      const label = String(title || "").trim();
      if (!label) return;
      const key = `${type || ""}:${label.toLowerCase()}`;
      const prev = map.get(key) || { key, label, amount: 0 };
      prev.amount += (Number(cents) || 0) / 100;
      map.set(key, prev);
    };
    for (const app of source.cart_level_discount_applications || []) {
      add(app.title, app.type, app.total_allocated_amount);
    }
    for (const item of source.items || []) {
      for (const alloc of item.line_level_discount_allocations || []) {
        const da = alloc.discount_application || {};
        add(da.title, da.type, alloc.amount);
      }
    }
    return [...map.values()].filter((d) => d.amount > 0);
  }

  function money(value) {
    const sym = currency === "INR" ? "₹" : `${currency} `;
    return `${sym}${(Number(value) || 0)
      .toFixed(2)
      .replace(/\B(?=(\d{3})+(?!\d))/g, ",")}`;
  }

  async function startConfetti() {
    const canvas = canvasEl;
    if (!canvas) return;
    cancelConfetti();
    const confetti = await loadConfetti();
    // The dialog can auto-dismiss while the CDN script is still in flight.
    if (!confetti || canvasEl !== canvas) return;
    const fire = confetti.create(canvas, { resize: true });
    confettiInstance = fire;
    const colors = [
      "#3173e3",
      "#3173e3",
      "#1a7f37",
      "#fbbf24",
      "#ec4899",
      "#ffffff",
    ];
    const blast = (count, opts) =>
      fire({ origin: { x: 0.5, y: 0.5 }, colors, particleCount: count, ...opts });
    blast(362, { spread: 360, startVelocity: 55, scalar: 1.3 });
    blast(224, { spread: 140, startVelocity: 80, scalar: 1.2 });
    blast(173, { spread: 200, startVelocity: 48, decay: 0.92, scalar: 1.05 });
    blast(138, { angle: 60, spread: 80, startVelocity: 70, origin: { x: 0, y: 0.6 } });
    blast(138, { angle: 120, spread: 80, startVelocity: 70, origin: { x: 1, y: 0.6 } });
  }

  function cancelConfetti() {
    if (confettiInstance) {
      confettiInstance.reset();
      confettiInstance = null;
    }
  }

  function trigger(title, amount) {
    celebration = { title, amount };
    clearTimeout(dismissTimer);
    dismissTimer = setTimeout(close, 4000);
    tick().then(startConfetti);
  }

  function close() {
    celebration = null;
    clearTimeout(dismissTimer);
    cancelConfetti();
  }

  $effect(() => {
    const list = discountList(cart);
    const nextKeys = new Set(list.map((d) => d.key));
    if (!isCartReady) {
      prevKeys = nextKeys;
      return;
    }
    if (!armed) {
      prevKeys = nextKeys;
      armed = true;
      if (list.length > 0) {
        const top = list.reduce((best, d) => (d.amount > best.amount ? d : best));
        trigger(top.label, top.amount);
      }
      return;
    }
    const gained = list.filter((d) => !prevKeys.has(d.key));
    prevKeys = nextKeys;
    if (gained.length > 0) {
      const top = gained.reduce((best, d) => (d.amount > best.amount ? d : best));
      trigger(top.label, top.amount);
    }
  });

  onDestroy(() => {
    clearTimeout(dismissTimer);
    cancelConfetti();
  });
</script>

{#if celebration}
  <div class="ck-celebrate" role="dialog" aria-live="polite">
    <canvas class="ck-celebrate__confetti" bind:this={canvasEl}></canvas>
    <div class="ck-celebrate__card">
      <img class="ck-celebrate__icon" src={DISCOUNT_ICON} alt="" aria-hidden="true" />
      <h3 class="ck-celebrate__title">"{celebration.title}" applied</h3>
      <p class="ck-celebrate__subtitle">
        You just saved {money(celebration.amount)} on this order!
      </p>
      <button type="button" class="ck-celebrate__btn" onclick={close}>
        {T("celebration_thanks")}
      </button>
    </div>
  </div>
{/if}

<style>
  .ck-celebrate {
    position: absolute;
    inset: 0;
    z-index: 2147483647;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
    background: rgba(0, 0, 0, 0.4);
    border-radius: inherit;
    animation: ck-celebrate-fade 200ms ease-out both;
  }

  .ck-celebrate__confetti {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }

  .ck-celebrate__card {
    position: relative;
    width: 100%;
    max-width: 340px;
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    padding: 24px 24px 0;
    background: #ffffff;
    border-radius: 16px;
    box-shadow: 0 24px 60px rgba(15, 23, 42, 0.28);
    overflow: hidden;
    animation: ck-celebrate-pop 260ms cubic-bezier(0.34, 1.56, 0.64, 1) both;
  }

  .ck-celebrate__icon {
    width: 48px;
    height: 48px;
    object-fit: contain;
    margin-bottom: 12px;
    display: block;
  }

  .ck-celebrate__title {
    margin: 0;
    color: #1c1c1e;
    font-family: var(--font-family-base);
    font-size: 18px;
    line-height: 26px;
    font-weight: 600;
  }

  .ck-celebrate__subtitle {
    margin: 4px 0 16px;
    color: #6b7280;
    font-family: var(--font-family-base);
    font-size: 14px;
    line-height: 20px;
    font-weight: 400;
  }

  .ck-celebrate__btn {
    width: calc(100% + 48px);
    margin: 0 -24px;
    padding: 10px 16px;
    border: none;
    border-top: 1px solid var(--hairline);
    background: transparent;
    color: var(--color-blue);
    font-family: var(--font-family-base);
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
  }

  .ck-celebrate__btn:active {
    background: #f8fafc;
  }

  @keyframes ck-celebrate-fade {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }

  @keyframes ck-celebrate-pop {
    from {
      opacity: 0;
      transform: scale(0.9);
    }
    to {
      opacity: 1;
      transform: scale(1);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .ck-celebrate,
    .ck-celebrate__card {
      animation: none;
    }
  }
</style>
