<script>
  import { onMount } from "svelte";
  import { settingsStore } from "./stores/settingsStore.js";
  import { appStore, actions } from "./stores/buttonManager.js";
  import { codOrderFlowStore } from "./stores/codOrderFlowStore.js";
  import MobileLayout from "./components/layouts/MobileLayout.svelte";
  import "./styles/App.css";
  import "./styles/App.mobile.css";
  import "./styles/App.desktop.css";
  import "./styles/animations.css";
  import {
    mergeCampaignFromSearch,
    persistCampaignFromParentPayload,
  } from "./utils/campaignAttribution.js";

  // Lazy load heavy utilities (declared here, loaded in onMount)
  let injectIframeStyles,
    setupVisualViewportHeight,
    setupMobileViewportHandlers,
    setupBfcacheHandler;

  let cleanupViewportHeight = () => {};
  let cleanupMobileHandlers = () => {};

  // Expose store and actions to parent window for Liquid file communication
  if (typeof window !== "undefined") {
    const win =
      /** @type {Window & typeof globalThis & { appStore?: typeof appStore; appActions?: typeof actions; __showProcessingScreen?: boolean }} */ (
        window
      );

    win.appStore = appStore;
    win.appActions = actions;
    // The thank-you flow has its own store, and the admin preview needs it to
    // show the order confirmation copy on the screen it belongs to.
    win.codOrderFlowStore = codOrderFlowStore;
  }

  // Phase 5: Cart Synchronization & State Management
  onMount(() => {
    // Cross-origin iframe: parent storefront holds Meta fbp/fbc in localStorage; request via postMessage.
    const onMetaAttributionMessage = (e) => {
      try {
        if (!e?.data || typeof e.data !== "object") return;
        if (e.data.type !== "CODK_SET_META_ATTRIBUTION") return;
        const p = e.data.payload;
        if (p && typeof p === "object") {
          /** @type {Window & { __codk_meta_click_data?: object }} */ (window).__codk_meta_click_data = p;
          if (p.campaign && typeof p.campaign === "object") {
            persistCampaignFromParentPayload(p.campaign);
          }
        }
      } catch (_err) {}
    };
    if (typeof window !== "undefined") {
      mergeCampaignFromSearch(window.location.search || "");
      window.addEventListener("message", onMetaAttributionMessage);
      try {
        if (window.parent && window.parent !== window) {
          window.parent.postMessage({ type: "CODK_REQUEST_META_ATTRIBUTION" }, "*");
        }
      } catch (_e) {}
    }

    // Restore persistent sign-in from localStorage when settings already in session (e.g. same-tab navigation)
    (async () => {
      try {
        const { getSessionValue, setSessionValue } = await import("./services/sessionService.js");
        const { getShopDomain } = await import("./utils/helpers.js");
        const { restorePersistentSigninIfEnabled } = await import("./services/persistentSigninStorage.js");
        const settings = $settingsStore;
        const shopDomain = getShopDomain();
        if (settings && shopDomain) {
          await restorePersistentSigninIfEnabled(settings, shopDomain, {
            setSessionValue,
            appStore,
            actions,
          });
        }
      } catch (_e) {}
    })();

    // Handle Razorpay callback redirect: URL has razorpay_success=1&order_number=... after UPI/redirect payment (e.g. mobile)
    const handleRazorpayRedirectSuccess = async () => {
      try {
        if (typeof window === "undefined" || !window.location.search) return;
        const params = new URLSearchParams(window.location.search);
        const success = params.get("razorpay_success");
        const orderNumber = params.get("order_number");
        const orderStatusUrlParam = params.get("order_status_url");
        const orderStatusUrl = orderStatusUrlParam ? decodeURIComponent(orderStatusUrlParam) : null;
        if (success !== "1" || !orderNumber) return;

        const { setSessionValue, removeSessionValue } = await import("./utilities/otpUtils.js");
        const { clearCart } = await import("./services/cartService.js");
        const { otpStoreActions } = await import("./stores/otpStore.js");
        const { codOrderFlowStore } = await import("./stores/codOrderFlowStore.js");

        setSessionValue("razorpay_redirect_order_number", orderNumber);
        setSessionValue("razorpay_redirect_success", "1");
        if (orderStatusUrl) setSessionValue("razorpay_redirect_order_status_url", orderStatusUrl);
        try {
          await clearCart();
          otpStoreActions.setCurrentCartData(null);
        } catch (_e) {}

        // Show full-screen Thank You flow (same as embedded success) so mobile redirect path matches COD/prepaid UX
        actions.openModal();
        codOrderFlowStore.setShow(true);
        codOrderFlowStore.setProcessing(false);
        codOrderFlowStore.setOrderResult({
          orderNumber,
          orderStatusUrl: orderStatusUrl || undefined,
          paymentMethod: "Prepaid",
        });
        actions.setShowCodOrderFlow(true);

        removeSessionValue("razorpay_redirect_order_number");
        removeSessionValue("razorpay_redirect_success");
        removeSessionValue("razorpay_redirect_order_status_url");
        const url = window.location.pathname + (window.location.hash || "");
        window.history.replaceState({}, "", url);
      } catch (_e) {}
    };
    handleRazorpayRedirectSuccess();

    const checkAndHandleBuyNow = async () => {
      try {
        if (typeof window === "undefined") return;

        // Check session storage for buy now flag
        const currentWindowFlag =
          window.sessionStorage?.getItem("cod_king_isBuyNow") === "true";

        const parentWindowFlag =
          window.parent &&
          window.parent !== window &&
          window.parent.sessionStorage?.getItem("cod_king_isBuyNow") === "true";
        const isBuyNow = currentWindowFlag || parentWindowFlag;

        if (isBuyNow) {
          actions.setIsBuyNowButton(true);
        } else {
          actions.setIsBuyNowButton(false);
        }
      } catch (_error) {}
    };

    // Subscribe to modal open state and call checkAndHandleBuyNow when modal opens
    let previousIsOpen = false;

    const unsubscribeModal = appStore.subscribe((state) => {
      // Only call when modal transitions from closed to open
      if (!previousIsOpen && state.isOpen) {
        checkAndHandleBuyNow();
      }

      previousIsOpen = state.isOpen;
    });

    // Load and initialize iframe utilities (async import handled with .then())
    import("./utils/iframeStyles.js").then((iframeUtils) => {
      injectIframeStyles = iframeUtils.injectIframeStyles;
      setupVisualViewportHeight = iframeUtils.setupVisualViewportHeight;
      setupMobileViewportHandlers = iframeUtils.setupMobileViewportHandlers;
      setupBfcacheHandler = iframeUtils.setupBfcacheHandler;

      // Inject iframe CSS into parent window
      if (injectIframeStyles) injectIframeStyles();

      // Set up visual viewport height tracking
      if (setupVisualViewportHeight) {
        const cleanup = setupVisualViewportHeight();

        // @ts-ignore - cleanup function type is compatible
        cleanupViewportHeight =
          typeof cleanup === "function" ? cleanup : () => {};
      }

      // Setup mobile viewport handlers (zoom, pull-to-refresh, double-tap)
      if (setupMobileViewportHandlers) {
        const cleanup = setupMobileViewportHandlers();

        // @ts-ignore - cleanup function type is compatible
        cleanupMobileHandlers =
          typeof cleanup === "function" ? cleanup : () => {};
      }
    });

    return () => {
      if (typeof window !== "undefined") {
        window.removeEventListener("message", onMetaAttributionMessage);
      }
      cleanupViewportHeight();
      cleanupMobileHandlers();
      unsubscribeModal();
    };
  });

  function handleClose() {
    actions.closeModal();

    try {
      if (typeof window.parent !== "undefined" && window.parent.postMessage) {
        window.parent.postMessage("codk-close-modal", "*");
      }
    } catch (_error) {}
  }
</script>

<MobileLayout onClose={handleClose} />
