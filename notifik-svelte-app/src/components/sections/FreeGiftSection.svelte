<script>
  import otpStore from "../../stores/otpStore.js";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { syncFreeGifts, FREE_GIFT_PROPERTY } from "../../services/freeGiftService.js";

  let config = $derived($settingsStore?.freeGift ?? $settingsStore?.free_gift ?? null);
  let cart = $derived($otpStore.currentCartData || null);
  let cartReady = $derived($otpStore.isCartReady && !$otpStore.isSummaryOptimistic);
  let items = $derived(cart?.items || []);

  let lastSignature = "";

  const signatureOf = (list) =>
    list.map((item) => `${item.key}:${item.quantity}:${item.final_line_price}:${item.properties?.[FREE_GIFT_PROPERTY] || ""}`).join("|");

  $effect(() => {
    if (!config?.enabled || !cartReady || !cart?.token) return;
    const signature = signatureOf(items);
    if (signature === lastSignature) return;
    lastSignature = signature;
    syncFreeGifts(config, cart);
  });
</script>
