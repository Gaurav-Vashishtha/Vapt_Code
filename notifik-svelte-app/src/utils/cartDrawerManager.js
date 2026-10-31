import { getSessionValue } from "../services/sessionService.js";


import { postToWindow } from "./parentMessaging";
export const QUICK_VIEW_CONTAINERS = [
  ".quick-options-drawer",
  ".quick-add-modal",
  "quick-view"
];

const CART_DRAWER_LAYOUT = [
  ".cart-drawer",
  "#halo-cart-sidebar",
  ".halo-cart-sidebar",
  "#cart-drawer-container",
  "#shopify-section-cart-drawer",
  "#mini-cart-drawer",
  "#mini-cart",
  ".mini-cart",
  ".saanj-cart-drawer",
  "#sidebar-cart-saanj",
  "#CartDrawer",
  ".dropdn-modal-minicart",
  "#dropdnMinicartPopup",
  ".quick-buy-drawer",
  "#quick-buy-drawer",
  "#sidebar-cart",
  "#CartContainer",
  "#js-minicart",
  "#mini-product-item",
  ".popup-cart",
  "#cart-notification",
  ".js-drawer",
  ".quick-add-modal",
  ".menu-opening",
  ".quick-cart__container",
  ".purchase-confirmation-popup",
  ".icart-cart-main",
  ".minicart__wrapper",
  ".amtCartDrawer",
  "#rebuy-cart",
  ".codk-drawer-layout",
  ".drawer-cd-up-app-Ksl",
  ".halo-quick-view-popup",
  ".halo-popup-wrapper",
  ".mini-cart-content",
  ".picky-cart__content",
  ".xboost-slide-cart-width ",
  ".xboost-cart-slide-vt",
  ".xb-cart-drawer-wrapper",
  "#t4s-mini_cart",
  ".bls-minicart-content",
  ".js-minicart",
  ".minicart",
  ".kaktusc-cart__body",
  ".eascMiniCartDiv",
  ".ea-sticky-cart-backdrop",
  ".easc-stickyCartDiv",
  ".eascStickyAddToCartBar",
  "#CartDrawer-Overlay",
  "#corner-cowi-interior-wrapper",
  ".jas-mini-cart",
  ".jas-push-menu",
  "#cart-drawer",
  "#monster-cart-wrapper",
  "cart-drawer",
  "#monster-upsell-cart",
  ".Drawer--fromRight",
  "#dropdown-cart",
  "#MinimogCartDrawer",
  "#aov-cart-drawer",
  ".AOV-CartDrawer--open",
  "#atlas-upsell-cart-not-empty-cart-container",
  ".slideout__drawer-right",
  "#offcanvas-cart",
  ".opus-drawer-container",
  ".opus-container-content",
  "#corner-widget-page-wrapper",
  "#icartMainContent",
  ".icart-content",
  ".drawer__underlay",
  ".drawer--right",
  ".dialog-drawer",
  ".cart-drawer__inner",
  "cart-items-component",
  ".cart-items-component",
  ".cart-drawer__header",
  ".cart-drawer__content",
  ".cart-items__wrapper",
  ".cart__ctas",
  ".cart__checkout-button",
  ".cart-drawer__summary",
  ".quick-cart__wrapper",
  ".quick-cart__overlay",
  ".PageOverlay",
  ".Drawer__Overlay",
  "[data-drawer-overlay]",
  ".cart-popup",
  ".cart-modal",
  ".cart-wrapper",
  ".cart-sidebar",
  ".cart-flyout",
  ".gokwik-checkout-button",
  ".dynamic-checkout-button",
  "#cart-form",
  ".cart-form",
  ".shopify-cart-form",
  ".cc-popup-container",
  "dialog[data-fluco-dialog='cartDrawer']",
  "dialog.color-drawer.drawer",
  "cart-drawer",
  "drawer-inner",
  ".drawer-footer",
  ".cart-drawer__footer-content",
  ".cart-items",
  "form#cart-drawer-form",
  "dialog[data-fluco-dialog='cartDrawer'] cart-drawer",
  ".AOV-CartDrawer-Overlay",
  ".AOV-CartDrawer-Checkout",
];

// Themes built on a dialog component (Horizon's <dialog-component>, <cart-drawer-component>) must be
// closed and reopened through it: a bare dialog.close() leaves its outside-click listener attached
// and its body scroll lock on, so the next tap on the cart icon opens the drawer and that same tap
// closes it again, for good.
const dialogOwner = (el) => {
  const body = el && el.ownerDocument && el.ownerDocument.body;
  for (let n = el && el.parentElement; n && n !== body; n = n.parentElement) {
    if (typeof n.closeDialog === "function" && typeof n.showDialog === "function") return n;
  }
  return null;
};
const closeDialogEl = (el) => {
  const owner = /** @type {any} */ (dialogOwner(el));
  if (owner) {
    try {
      owner.closeDialog();
      return;
    } catch (_e) {}
  }
  /** @type {any} */ (el).close();
};
const openDialogEl = (el) => {
  const owner = /** @type {any} */ (dialogOwner(el));
  if (owner) {
    try {
      owner.showDialog();
      return;
    } catch (_e) {}
  }
  /** @type {any} */ (el).showModal();
};

const getParentDocument = () => {
  try {
    if (typeof window !== "undefined" && window.parent && window.parent !== window)
      return window.parent.document;
    return document;
  } catch (_) {
    return document;
  }
};

const getParentWindow = () => {
  if (typeof window === "undefined") return null;
  try {
    if (window.parent && window.parent !== window) return window.parent;
    return window;
  } catch (_) {
    return window;
  }
};

const getCartDrawerLayouts = () => {
  const settings = getSessionValue("settingSession");
  const { preV2CartDrawerLayoutSelectors } = settings || {};

  if (preV2CartDrawerLayoutSelectors) {
    return CART_DRAWER_LAYOUT.concat(
      preV2CartDrawerLayoutSelectors
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean),
    );
  }
  return CART_DRAWER_LAYOUT;
};

const isButtonBlockingRelevant = (settings) => {
  if (!settings) return false;
  const loginFlow =
    settings.preIsLoginEnabled === true ||
    settings.preIsLoginEnabled === "true" ||
    settings.pre_is_login_enabled === true ||
    settings.pre_is_login_enabled === "true";
  if (loginFlow) return false;

  const preOrderOtp =
    settings.enablePreOrderOtp === true ||
    settings.enablePreOrderOtp === "true" ||
    settings.enable_pre_order_otp === true ||
    settings.enable_pre_order_otp === "true";
  const partialPayment =
    settings.partialPaymentEnabled === true ||
    settings.partialPaymentEnabled === "true" ||
    settings.partial_payment_enabled === true ||
    settings.partial_payment_enabled === "true";
  if (!preOrderOtp && !partialPayment) return false;

  const prefilledAddress =
    settings.isPrefilledAddressEnabled === true ||
    settings.isPrefilledAddressEnabled === "true" ||
    settings.is_prefilled_address_enabled === true ||
    settings.is_prefilled_address_enabled === "true";
  const verifiedNumberData = getSessionValue("verifiedNumberData", null);
  const isOtpVerified = !!(
    verifiedNumberData && verifiedNumberData.isOTPVerified
  );
  if (isOtpVerified && !prefilledAddress && !partialPayment) return false;

  return true;
};

export const CODK_REATTACH_BUTTON_BLOCK_TYPE = "codking:reattachButtonBlock";
const NOTIFY_REATTACH_THROTTLE_MS = 500;
let cartDrawerButtonBlockDisconnect = null;

export const attachCartDrawerLayoutMutationForButtonBlock = () => {
  const doc = getParentDocument();
  const cartDrawerLayouts = getCartDrawerLayouts();
  const observers = [];
  const observedRoots = new WeakSet();
  let lastNotifyTime = 0;

  const notifyParentToReattachButtonBlock = (forceImmediate = false) => {
    const now = Date.now();
    if (!forceImmediate && now - lastNotifyTime < NOTIFY_REATTACH_THROTTLE_MS)
      return;
    lastNotifyTime = now;
    try {
      const targetWindow =
        typeof window !== "undefined" && window.parent !== window
          ? window.parent
          : window;
      postToWindow(targetWindow, { type: CODK_REATTACH_BUTTON_BLOCK_TYPE });
    } catch (_e) {}
  };

  const attachObserversToMatchingElements = () => {
    cartDrawerLayouts.forEach((selector) => {
      try {
        const elements = doc.querySelectorAll(selector);
        elements.forEach((el) => {
          if (observedRoots.has(el)) return;
          observedRoots.add(el);
          const observer = new MutationObserver(() => {
            notifyParentToReattachButtonBlock();
          });
          observer.observe(el, { childList: true, subtree: true });
          observers.push({ observer, element: el });
        });
      } catch (e) {
        // Skip invalid selectors
      }
    });
  };

  const isCartDrawerRelated = (node) => {
    if (!node || node.nodeType !== 1) return false;
    const el = /** @type {Element} */ (node);
    for (const selector of cartDrawerLayouts) {
      try {
        if (el.matches && el.matches(selector)) return true;
        if (el.querySelector && el.querySelector(selector)) return true;
        let parent = el.parentElement;
        while (parent) {
          if (parent.matches && parent.matches(selector)) return true;
          parent = parent.parentElement;
        }
      } catch (_) {}
    }
    return false;
  };

  attachObserversToMatchingElements();

  notifyParentToReattachButtonBlock(true);

  const bodyObserver = new MutationObserver((mutations) => {
    let relevant = false;
    for (const mutation of mutations) {
      if (mutation.addedNodes.length === 0) continue;
      for (const node of mutation.addedNodes) {
        if (isCartDrawerRelated(node)) {
          relevant = true;
          break;
        }
        if (node.nodeType === 1) {
          const elNode = /** @type {Element} */ (node);
          for (const selector of cartDrawerLayouts) {
            try {
              if (elNode.querySelector && elNode.querySelector(selector)) {
                relevant = true;
                break;
              }
            } catch (e) {}
          }
        }
      }
      if (relevant) break;
    }
    if (relevant) {
      attachObserversToMatchingElements();
      notifyParentToReattachButtonBlock();
    }
  });

  const body = doc.body || doc.documentElement;
  if (body) {
    bodyObserver.observe(body, { childList: true, subtree: true });
    observers.push({ observer: bodyObserver, element: null });
  }

  const disconnect = () => {
    observers.forEach(({ observer }) => observer.disconnect());
    observers.length = 0;
    cartDrawerButtonBlockDisconnect = null;
  };

  cartDrawerButtonBlockDisconnect = disconnect;
  return { disconnect };
};

export const disconnectCartDrawerButtonBlockObservers = () => {
  if (cartDrawerButtonBlockDisconnect) {
    cartDrawerButtonBlockDisconnect();
    cartDrawerButtonBlockDisconnect = null;
  }
};

export const initializeCartDrawerHiding = () => {
  const doc = getParentDocument();
  const cartDrawerLayouts = getCartDrawerLayouts();
  let discoveredElements = [];
  let hiddenElementStates = new Map();

  function discoverCartElements() {
    discoveredElements = [];
    cartDrawerLayouts.forEach((selector) => {
      try {
        const elements = Array.from(doc.querySelectorAll(selector));
        if (elements.length > 0) discoveredElements.push(...elements);
      } catch (_e) {}
    });
    discoveredElements = [...new Set(discoveredElements)];
    return discoveredElements;
  }

  function storeElementState(element) {
    const state = {
      display: element.style.display || "",
      visibility: element.style.visibility || "",
      opacity: element.style.opacity || "",
      zIndex: element.style.zIndex || "",
      transform: element.style.transform || "",
      pointerEvents: element.style.pointerEvents || "",
      ariaHidden: element.getAttribute("aria-hidden"),
      hidden: element.hasAttribute("hidden"),
      isDialog: element.tagName === "DIALOG",
      wasOpen: element.tagName === "DIALOG" && element.hasAttribute("open"),
      hadScrollLock: element.hasAttribute("scroll-lock"),
      showClass: element.classList.contains("show"),
      activeClass: element.classList.contains("active"),
      openClass: element.classList.contains("open"),
      visibleClass: element.classList.contains("visible"),
      isOpenClass: element.classList.contains("is-open"),
      isActiveClass: element.classList.contains("is-active"),
    };

    hiddenElementStates.set(element, state);
    return state;
  }

  function hideDrawer() {
    const elements = discoverCartElements();
    if (elements.length === 0) return;

    let hiddenCount = 0;

    elements.forEach((element) => {
      if (!element || !doc.contains(element)) return;

      storeElementState(element);

      if (element.tagName === "DIALOG") {
        try {
          if (element.hasAttribute("open")) {
            closeDialogEl(element);
          }
        } catch (_e) {}
      }

      element.style.display = "none";
      element.style.visibility = "hidden";
      element.style.opacity = "0";
      element.style.pointerEvents = "none";
      element.style.zIndex = "-9999";
      element.style.transform = "translateX(-100vw)";
      element.setAttribute("aria-hidden", "true");
      element.setAttribute("hidden", "true");
      element.removeAttribute("scroll-lock");

      const classesToRemove = [
        "show",
        "active",
        "open",
        "visible",
        "is-open",
        "is-active",
      ];
      classesToRemove.forEach((cls) => element.classList.remove(cls));
      element.classList.add("codking-hidden");

      hiddenCount++;
    });

    const bodyClasses = [
      "js-drawer-open",
      "js-drawer-open-right",
      "drawer-open",
      "cart-open",
      "scroll-lock",
      "no-scroll",
      "overflow-hidden",
      "modal-open",
      "cart-drawer-open",
      "has-drawer-open",
      "minicart-open",
    ];

    bodyClasses.forEach((cls) => {
      doc.documentElement.classList.remove(cls);
      doc.body.classList.remove(cls);
    });

    doc.body.style.overflow = "";
    doc.documentElement.style.overflow = "";

    if (!doc.getElementById("codking-universal-cart-style")) {
      const style = doc.createElement("style");
      style.id = "codking-universal-cart-style";

      const mainSelectors = cartDrawerLayouts.join(",\n");
      const childSelectors = cartDrawerLayouts.map((s) => `${s} *`).join(",\n");

      style.textContent = `
        ${mainSelectors},
        ${childSelectors},
        .codking-hidden,
        .codking-hidden * {
          display: none !important;
          visibility: hidden !important;
          opacity: 0 !important;
          pointer-events: none !important;
          cursor: default !important;
          z-index: -9999 !important;
          transform: translateX(-100vw) !important;
        }
      `;
      doc.head.appendChild(style);
    }

  }

  function restoreDrawer() {

    const hideStyle = doc.getElementById("codking-universal-cart-style");
    if (hideStyle) {
      hideStyle.remove();
    }

    let restoredCount = 0;

    hiddenElementStates.forEach((state, element) => {
      if (!element || !doc.contains(element)) return;

      element.style.display = state.display;
      element.style.visibility = state.visibility;
      element.style.opacity = state.opacity;
      element.style.pointerEvents = state.pointerEvents;
      element.style.zIndex = state.zIndex;
      element.style.transform = state.transform;

      if (state.ariaHidden) {
        element.setAttribute("aria-hidden", state.ariaHidden);
      } else {
        element.removeAttribute("aria-hidden");
      }

      if (!state.hidden) {
        element.removeAttribute("hidden");
      }

      if (state.isDialog) {
        if (state.wasOpen) {
          try {
            openDialogEl(element);
          } catch (e) {
            element.setAttribute("open", "");
          }
        }
        if (state.hadScrollLock) {
          element.setAttribute("scroll-lock", "");
        }
      }

      const classStates = {
        show: state.showClass,
        active: state.activeClass,
        open: state.openClass,
        visible: state.visibleClass,
        "is-open": state.isOpenClass,
        "is-active": state.isActiveClass,
      };

      Object.entries(classStates).forEach(([className, shouldHave]) => {
        if (shouldHave) {
          element.classList.add(className);
        }
      });

      element.classList.remove("codking-hidden");
      restoredCount++;
    });

    hiddenElementStates.clear();
  }

  if (typeof window !== "undefined") {
    const parentWindow = window.parent || window;
    parentWindow.codkingHideDrawer = hideDrawer;
    parentWindow.codkingRestoreDrawer = restoreDrawer;
    parentWindow.codkingDiscoverCarts = discoverCartElements;

    parentWindow.addEventListener("codking:otpModalOpened", hideDrawer);
    parentWindow.addEventListener("codking:otpModalClosed", restoreDrawer);
  }

  setTimeout(() => discoverCartElements(), 1000);

  return { hideDrawer, restoreDrawer, discoverCartElements };
};

export const initializeCartDrawerHidingLogicTwo = () => {
  const doc = getParentDocument();
  const cartDrawerLayouts = getCartDrawerLayouts();
  let colorDrawerStates = new Map();

  function storeDrawerState(drawer) {
    const state = {
      wasOpen: drawer.hasAttribute("open"),
      hadScrollLock: drawer.hasAttribute("scroll-lock"),
      display: drawer.style.display || "",
      visibility: drawer.style.visibility || "",
      opacity: drawer.style.opacity || "",
      zIndex: drawer.style.zIndex || "",
      ariaHidden: drawer.getAttribute("aria-hidden"),
    };
    colorDrawerStates.set(drawer, state);
    return state;
  }

  function hideDrawer() {
    let hiddenCount = 0;

    cartDrawerLayouts.forEach((selector) => {
      try {
        const drawers = doc.querySelectorAll(selector);
        drawers.forEach((drawer) => {
          if (!drawer || !doc.contains(drawer)) return;

          storeDrawerState(drawer);

          if (drawer.tagName === "DIALOG" && drawer.hasAttribute("open")) {
            try {
              closeDialogEl(drawer);
            } catch (_e) {}
          }

          drawer.style.display = "none";
          drawer.style.visibility = "hidden";
          drawer.style.opacity = "0";
          drawer.style.pointerEvents = "none";
          drawer.style.zIndex = "-9999";
          drawer.setAttribute("aria-hidden", "true");
          drawer.setAttribute("hidden", "true");
          drawer.removeAttribute("scroll-lock");
          drawer.classList.add("codking-hidden");

          hiddenCount++;
        });
      } catch (e) {
        // Skip invalid selectors
      }
    });

    if (!doc.getElementById("codking-color-drawer-style")) {
      const style = doc.createElement("style");
      style.id = "codking-color-drawer-style";
      const mainSelectors = cartDrawerLayouts.join(",\n");
      const childSelectors = cartDrawerLayouts.map((s) => `${s} *`).join(",\n");

      style.textContent = `
        ${mainSelectors},
        ${childSelectors},
        .codking-hidden,
        .codking-hidden * {
          display: none !important;
          visibility: hidden !important;
          opacity: 0 !important;
          pointer-events: none !important;
          z-index: -9999 !important;
        }
      `;
      doc.head.appendChild(style);
    }

  }

  function restoreDrawer() {
    const currentSettings = getSessionValue("settingSession") || {};
    const currentCondition = Number(
      currentSettings?.preV2OverwritePopupCondition,
    );
    if (currentCondition === 6) return;

    const hideStyle = doc.getElementById("codking-color-drawer-style");
    if (hideStyle) {
      hideStyle.remove();
    }

    colorDrawerStates.forEach((state, drawer) => {
      if (!drawer || !doc.contains(drawer)) return;

      drawer.style.display = state.display;
      drawer.style.visibility = state.visibility;
      drawer.style.opacity = state.opacity;
      drawer.style.zIndex = state.zIndex;

      if (state.ariaHidden) {
        drawer.setAttribute("aria-hidden", state.ariaHidden);
      } else {
        drawer.removeAttribute("aria-hidden");
      }

      drawer.removeAttribute("hidden");

      if (state.wasOpen) {
        try {
          openDialogEl(drawer);
        } catch (e) {
          drawer.setAttribute("open", "");
        }
      }

      if (state.hadScrollLock) {
        drawer.setAttribute("scroll-lock", "");
      }

      drawer.classList.remove("codking-hidden");
    });

    colorDrawerStates.clear();
  }

  if (typeof window !== "undefined") {
    const parentWindow = window.parent || window;
    parentWindow.codkingHideDrawer = hideDrawer;
    parentWindow.codkingRestoreDrawer = restoreDrawer;
    parentWindow.addEventListener("codking:otpModalOpened", hideDrawer);
    parentWindow.addEventListener("codking:otpModalClosed", restoreDrawer);
  }

  return { hideDrawer, restoreDrawer };
};

export const initializeCartDrawerHidingLogicThree = () => initializeCartDrawerHiding();
export const initializeCartDrawerHidingLogicFour = () => initializeCartDrawerHiding();

export const initializeCartDrawerHidingLogicFive = () => {
  const doc = getParentDocument();
  const cartDrawerLayouts = getCartDrawerLayouts();

  function hideDrawer() {
    let hiddenCount = 0;

    const dialogSelectors = [
      "dialog.cart-drawer__dialog",
      "dialog[open]",
      ".cart-drawer__dialog",
    ];

    dialogSelectors.forEach((selector) => {
      try {
        const dialogs = doc.querySelectorAll(selector);
        dialogs.forEach((dialog) => {
          if (!dialog || !doc.contains(dialog)) return;

          dialog.setAttribute(
            "data-codking-was-open",
            dialog.hasAttribute("open"),
          );
          dialog.setAttribute(
            "data-codking-scroll-lock",
            dialog.hasAttribute("scroll-lock"),
          );

          if (dialog.hasAttribute("open")) {
            try {
              closeDialogEl(dialog);
            } catch (e) {
              dialog.removeAttribute("open");
            }
          }

          dialog.style.display = "none";
          dialog.style.visibility = "hidden";
          dialog.setAttribute("aria-hidden", "true");
          dialog.removeAttribute("scroll-lock");

          hiddenCount++;
        });
      } catch (_) {}
    });

    if (!doc.getElementById("codking-dialog-cart-style")) {
      const style = doc.createElement("style");
      style.id = "codking-dialog-cart-style";
      style.textContent = `
        dialog.cart-drawer__dialog,
        dialog.cart-drawer__dialog *,
        .cart-drawer__inner,
        .cart-drawer__inner *,
        cart-items-component,
        cart-items-component *,
        .cart-items-component,
        .cart-items-component *,
        .cart-drawer__header,
        .cart-drawer__header *,
        .cart-drawer__content,
        .cart-drawer__content *,
        .cart__checkout-button,
        .cart__checkout-button *,
        #cart-form,
        #cart-form *,
        .cart-form,
        .cart-form * {
          display: none !important;
          visibility: hidden !important;
          opacity: 0 !important;
          pointer-events: none !important;
          cursor: default !important;
          z-index: -9999 !important;
          transform: translateX(-100vw) !important;
        }
      `;
      doc.head.appendChild(style);
    }

  }

  function restoreDrawer() {

    const hideStyle = doc.getElementById("codking-dialog-cart-style");
    if (hideStyle) {
      hideStyle.remove();
    }

    const dialogs = doc.querySelectorAll("[data-codking-was-open]");
    dialogs.forEach((dialog) => {
      const wasOpen = dialog.getAttribute("data-codking-was-open") === "true";
      const hadScrollLock =
        dialog.getAttribute("data-codking-scroll-lock") === "true";

      dialog.style.display = "";
      dialog.style.visibility = "";
      dialog.removeAttribute("aria-hidden");

      if (wasOpen) {
        try {
          openDialogEl(dialog);
        } catch (e) {
          dialog.setAttribute("open", "");
        }
      }

      if (hadScrollLock) {
        dialog.setAttribute("scroll-lock", "");
      }

      dialog.removeAttribute("data-codking-was-open");
      dialog.removeAttribute("data-codking-scroll-lock");
    });
  }

  if (typeof window !== "undefined") {
    const parentWindow = window.parent || window;
    parentWindow.codkingHideDrawer = hideDrawer;
    parentWindow.codkingRestoreDrawer = restoreDrawer;
    parentWindow.addEventListener("codking:otpModalOpened", hideDrawer);
    parentWindow.addEventListener("codking:otpModalClosed", restoreDrawer);
  }

  return { hideDrawer, restoreDrawer };
};

export const initializeCartDrawerHidingLogicSix = () => {
  const doc = getParentDocument();
  const cartDrawerLayouts = getCartDrawerLayouts();

  function closeCartDrawerSafely() {
    for (const selector of cartDrawerLayouts) {
      try {
        const element = doc.querySelector(selector);
        if (!element) continue;

        const elementAny = /** @type {any} */ (element);
        if (typeof elementAny.close === "function") {
          try {
            elementAny.close();
            return true;
          } catch (_e) {}
        }

        const dialog = element.querySelector("dialog[open]");
        if (dialog) {
          try {
            /** @type {HTMLDialogElement} */
            const dialogEl = /** @type {any} */ (dialog);
            closeDialogEl(dialogEl);
            dialogEl.removeAttribute("open");
            return true;
          } catch (_e) {}
        }

        if (element.tagName === "DIALOG" && element.hasAttribute("open")) {
          try {
            /** @type {HTMLDialogElement} */
            const dialogEl = /** @type {any} */ (element);
            closeDialogEl(dialogEl);
            dialogEl.removeAttribute("open");
            return true;
          } catch (_e) {}
        }
      } catch (_e) {}
    }

    return false;
  }

  function hideDrawer() {
    closeCartDrawerSafely();
  }

  if (typeof window !== "undefined") {
    const parentWindow = window.parent || window;
    parentWindow["codkingHideDrawer"] = hideDrawer;
    parentWindow.addEventListener("codking:otpModalOpened", hideDrawer);
  }

  return { hideDrawer };
};

const CODK_OVERLAY_IDS = ["codk-full-modal-svelte", "codk-modal-wrapper"];

const AOV_DRAWER_SELECTOR =
  "#aov-cart-drawer, .AOV-CartDrawer--open, .AOV-CartDrawer-Overlay";

const AOV_CLOSE_GLOBALS = [
  "aovCartDrawerClose",
  "AOVCartDrawerClose",
  "closeAovCartDrawer",
  "aovCloseCartDrawer",
];

const isAovDrawerPresent = (doc) => {
  try {
    return !!doc.querySelector(AOV_DRAWER_SELECTOR);
  } catch (_e) {
    return false;
  }
};

const getCodkOverlayBranch = (doc) => {
  const branch = new Set();
  CODK_OVERLAY_IDS.forEach((id) => {
    let node = doc.getElementById(id);
    while (
      node &&
      node.nodeType === 1 &&
      node !== doc.body &&
      node !== doc.documentElement
    ) {
      branch.add(node);
      node = node.parentElement;
    }
  });
  return Array.from(branch);
};

const releaseCodkOverlayInert = (doc) => {
  let released = 0;
  getCodkOverlayBranch(doc).forEach((node) => {
    const el = /** @type {any} */ (node);
    if (el.hasAttribute("inert")) {
      el.removeAttribute("inert");
      released++;
    }
    try {
      if (el.inert) {
        el.inert = false;
        released++;
      }
    } catch (_e) {}
    if (el.getAttribute("aria-hidden") === "true") {
      el.removeAttribute("aria-hidden");
      released++;
    }
  });
  return released;
};

const closeAovDrawerNatively = (win) => {
  if (!win) return false;

  const candidates = [...AOV_CLOSE_GLOBALS];
  try {
    Object.keys(win).forEach((key) => {
      if (/^aov/i.test(key) && /close/i.test(key) && !candidates.includes(key)) {
        candidates.push(key);
      }
    });
  } catch (_e) {}

  for (const name of candidates) {
    try {
      const fn = win[name];
      if (typeof fn !== "function") continue;
      fn.call(win);
      return true;
    } catch (_e) {}
  }
  return false;
};

const releaseAovScrollLock = (doc, win) => {
  const body = doc.body;
  if (!body || body.style.position !== "fixed") return;

  const offset = parseInt(body.style.top || "0", 10);
  body.style.position = "";
  body.style.top = "";
  body.style.width = "";
  body.style.overflow = "";
  doc.documentElement.style.overflow = "";

  if (Number.isFinite(offset) && offset < 0) {
    try {
      win?.scrollTo(0, Math.abs(offset));
    } catch (_e) {}
  }
};

export const initializeCartDrawerHidingAovSafe = () => {
  const doc = getParentDocument();
  const win = /** @type {any} */ (getParentWindow());
  const base = initializeCartDrawerHidingLogicSix();

  const observers = [];
  let observedTargets = [];
  let modalOpen = false;
  let releasing = false;

  const isOverlayVisible = () =>
    CODK_OVERLAY_IDS.some(
      (id) => doc.getElementById(id)?.getAttribute("data-visible") === "true",
    );

  const syncWithOverlayState = () => {
    if (releasing) return;
    releasing = true;
    try {
      const visible = isOverlayVisible();
      if (visible && !modalOpen) {
        hideDrawer();
      } else if (visible) {
        releaseCodkOverlayInert(doc);
      } else if (modalOpen) {
        releaseCodkOverlayInert(doc);
        modalOpen = false;
      }
    } finally {
      releasing = false;
    }
  };

  const detachObservers = () => {
    observers.forEach((observer) => observer.disconnect());
    observers.length = 0;
    observedTargets = [];
  };

  const attachObservers = () => {
    observers.forEach((observer) => observer.disconnect());
    observers.length = 0;

    observedTargets = getCodkOverlayBranch(doc);
    observedTargets.forEach((node) => {
      const observer = new MutationObserver(syncWithOverlayState);
      observer.observe(node, {
        attributes: true,
        attributeFilter: ["inert", "aria-hidden", "data-visible"],
      });
      observers.push(observer);
    });

    const body = doc.body;
    if (!body) return;

    const bodyObserver = new MutationObserver(() => {
      const targets = getCodkOverlayBranch(doc);
      const unchanged =
        targets.length === observedTargets.length &&
        targets.every((node, index) => node === observedTargets[index]);
      if (!unchanged) attachObservers();
      syncWithOverlayState();
    });
    bodyObserver.observe(body, { childList: true });
    observers.push(bodyObserver);
  };

  const hideDrawer = () => {
    modalOpen = true;
    const aovPresent = isAovDrawerPresent(doc);
    if (aovPresent) closeAovDrawerNatively(win);
    base.hideDrawer();
    releaseCodkOverlayInert(doc);
    if (aovPresent) releaseAovScrollLock(doc, win);
    attachObservers();
  };

  const restoreDrawer = () => {
    modalOpen = false;
  };

  if (win) {
    win.removeEventListener("codking:otpModalOpened", base.hideDrawer);
    win.codkingHideDrawer = hideDrawer;
    win.codkingRestoreDrawer = restoreDrawer;
    win.codkingReleaseOverlayInert = () => releaseCodkOverlayInert(doc);
    win.addEventListener("codking:otpModalOpened", hideDrawer);
    win.addEventListener("codking:otpModalClosed", restoreDrawer);
  }

  attachObservers();
  syncWithOverlayState();

  return { hideDrawer, restoreDrawer, disconnect: detachObservers };
};

// The COD form app embed (codk-form-*) applies the same popup condition to the theme cart drawer
// while its own form is open, and marks the page with data-codkf-drawer meanwhile. Only one of the
// two may touch the drawer: while that mark is there, this manager ignores the OTP modal events
// (and the matching "closed" event, so nothing is restored that it did not hide).
const CODKF_DRAWER_MARK = "data-codkf-drawer";
const codFormOwnsDrawer = () => {
  try {
    return getParentDocument().documentElement.hasAttribute(CODKF_DRAWER_MARK);
  } catch (_e) {
    return false;
  }
};

const installCodFormGuard = () => {
  const win = /** @type {any} */ (getParentWindow());
  if (!win || win.__codkDrawerGuard) return;
  win.__codkDrawerGuard = true;
  let skipped = false;
  // Capture listeners on the same target run before the strategies' own listeners.
  win.addEventListener(
    "codking:otpModalOpened",
    (event) => {
      skipped = codFormOwnsDrawer();
      if (skipped) event.stopImmediatePropagation();
    },
    true,
  );
  win.addEventListener(
    "codking:otpModalClosed",
    (event) => {
      if (!skipped) return;
      skipped = false;
      event.stopImmediatePropagation();
    },
    true,
  );
};

export const initializeCartDrawerManager = () => {
  installCodFormGuard();
  const settings = getSessionValue("settingSession");
  const strategy = settings?.preV2OverwritePopupCondition || 0;

  const executeStrategy = (strategyNum) => {
    switch (strategyNum) {
      case 0:
        initializeCartDrawerHidingLogicSix();
        return true;
      case 1:
        return initializeCartDrawerHidingLogicSix();
      case 2:
        return initializeCartDrawerHidingLogicTwo();
      case 3:
        return initializeCartDrawerHidingLogicThree();
      case 4:
        return initializeCartDrawerHidingLogicFour();
      case 5:
        return initializeCartDrawerHidingLogicFive();
      case 6:
        return initializeCartDrawerHiding();
      case 11:
      case "11":
        return initializeCartDrawerHidingAovSafe();
      default:
        return false;
    }
  };

  try {
    if (executeStrategy(strategy)) {
      if (isButtonBlockingRelevant(settings)) {
        attachCartDrawerLayoutMutationForButtonBlock();
      }
      return;
    }
  } catch (_error) {}

  if (strategy !== 1) {
    try {
      if (executeStrategy(1)) return;
    } catch (_err) {}
  }
};

export const hideCartDrawer = () => {};
export const showCartDrawer = () => {};

export default {
  initialize: initializeCartDrawerManager,
  hide: hideCartDrawer,
  show: showCartDrawer,
};
