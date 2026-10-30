<script>
  import { onMount, onDestroy, createEventDispatcher } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { loadRazorpayScript, initializeRazorpay } from "../../services/razorpayService.js";
  import BottomSlider from "./BottomSlider.svelte";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);

  const dispatch = createEventDispatcher();

  export let open = false;
  export let razorpayOptions = {};
  export let onSuccess = null;
  export let onFailure = null;

  let razorpayInstance = null;
  let isLoading = false;
  let error = null;
  let isRazorpayModalOpen = false;
  let hasInitialized = false;

  async function initializeRazorpayCheckout() {
    if (!razorpayOptions?.key || !razorpayOptions?.order_id) {
      error = "Missing Razorpay configuration";
      return;
    }

    try {
      isLoading = true;
      error = null;

      // Load Razorpay script
      await loadRazorpayScript();

      // @ts-ignore - Razorpay is loaded dynamically
      if (!window.Razorpay) {
        throw new Error("Razorpay SDK not loaded");
      }

      // Initialize Razorpay with all required options
      const optionsWithCallbacks = {
        ...razorpayOptions,
        onSuccess: (response) => {
          isRazorpayModalOpen = false;
          // Fire success first so parent sets orderSuccessMessage before we close (mobile stays on payment screen and shows message)
          dispatch('success', response);
          if (onSuccess != null) {
            try {
              if (typeof onSuccess === 'function') {
                onSuccess(response);
              } else if (typeof onSuccess === 'object' && typeof onSuccess.call === 'function') {
                onSuccess.call(null, response);
              }
            } catch (_error) {}
          }
          // Close after so user sees payment options screen with success message (especially on mobile)
          dispatch('close');
        },
        onFailure: (err) => {
          isRazorpayModalOpen = false;
          // Close BottomSlider immediately on failure/dismiss
          dispatch('close');
          if (onFailure) {
            onFailure(err);
          }
        }
      };
      
      razorpayInstance = await initializeRazorpay(optionsWithCallbacks);

      // Open Razorpay checkout
      if (razorpayInstance && typeof razorpayInstance.open === "function") {
        razorpayInstance.open();
        isRazorpayModalOpen = true;
        hasInitialized = true;
      }
    } catch (err) {
      error = err.message || "Failed to initialize payment";
      if (onFailure) {
        onFailure(err);
      }
    } finally {
      isLoading = false;
    }
  }

  $: if (open && razorpayOptions?.key && razorpayOptions?.order_id && !hasInitialized) {
    initializeRazorpayCheckout();
  }

  $: if (!open) {
    hasInitialized = false;
    isRazorpayModalOpen = false;
  }

  onDestroy(() => {
    if (razorpayInstance && razorpayInstance._messageHandler) {
      window.removeEventListener('message', razorpayInstance._messageHandler);
    }
    // Cleanup if needed
    razorpayInstance = null;
    hasInitialized = false;
  });
</script>

<BottomSlider
  {open}
  title={T("rzp_sheet_title")}
  subtitle="Secure payment powered by Razorpay"
  height="auto"
  showBackdrop={true}
  backdropClickable={false}
  showCloseButton={true}
  contentScrollable={false}
  on:close={() => {
    isRazorpayModalOpen = false;
    // Notify parent that BottomSlider was closed
    if (onFailure && typeof onFailure === 'function') {
      onFailure(new Error("Payment cancelled"));
    }
  }}
>
  <div class="razorpay-embed-container">
    {#if isLoading}
      <div class="loading-state">
        <div class="spinner"></div>
        <p>{T("rzp_loading")}</p>
      </div>
    {:else if error}
      <div class="error-state">
        <p class="error-message">{error}</p>
        <button
          class="retry-button"
          on:click={initializeRazorpayCheckout}
        >
          {T("rzp_retry")}
        </button>
      </div>
    {:else if isRazorpayModalOpen}
      <div class="razorpay-placeholder">
        <div class="spinner"></div>
        <p>{T("rzp_window_open")}</p>
        <p class="note">{T("rzp_window_note")}</p>
      </div>
    {:else}
      <div class="razorpay-placeholder">
        <p>{T("rzp_initializing")}</p>
      </div>
    {/if}
  </div>
</BottomSlider>

<style>
  .razorpay-embed-container {
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    min-height: 400px;
  }

  .loading-state,
  .error-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 1rem;
    padding: 2rem;
    text-align: center;
  }

  .spinner {
    width: 48px;
    height: 48px;
    border: 4px solid #f3f4f6;
    border-top: 4px solid #3399cc;
    border-radius: 50%;
    animation: spin 1s linear infinite;
  }

  @keyframes spin {
    0% {
      transform: rotate(0deg);
    }
    100% {
      transform: rotate(360deg);
    }
  }

  .error-message {
    color: #dc2626;
    font-size: 1rem;
    margin-bottom: 1rem;
  }

  .retry-button {
    background: #3399cc;
    color: white;
    border: none;
    padding: 0.75rem 1.5rem;
    border-radius: 6px;
    font-size: 1rem;
    cursor: pointer;
    transition: background 0.2s;
  }

  .retry-button:hover {
    background: #2980b9;
  }

  .razorpay-placeholder {
    text-align: center;
    padding: 2rem;
    color: #6b7280;
  }

  .note {
    font-size: 0.875rem;
    margin-top: 0.5rem;
    color: #9ca3af;
  }
</style>
