import { getSessionValue } from "./otpUtils";
import { CART_DRAWER_LAYOUT } from "./selectors";

const settings = getSessionValue("settingSession");
const { preV2CartDrawerLayoutSelectors } = settings || {};
const cartDrawerLayouts = preV2CartDrawerLayoutSelectors
  ? CART_DRAWER_LAYOUT.concat(
      preV2CartDrawerLayoutSelectors
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean)
    )
  : CART_DRAWER_LAYOUT;

export const initializeCartDrawerHiding = () => {
  let discoveredElements = [];
  let hiddenElementStates = new Map();

  function discoverCartElements() {
    console.log("Discovering cart elements...");

    discoveredElements = [];
    const foundSelectors = [];

    cartDrawerLayouts.forEach((selector) => {
      try {
        const elements = Array.from(document.querySelectorAll(selector));
        if (elements.length > 0) {
          discoveredElements.push(...elements);
          foundSelectors.push(`${selector} (${elements.length})`);
        }
      } catch (e) {
        // Skip invalid selectors
      }
    });

    // Remove duplicates
    discoveredElements = [...new Set(discoveredElements)];

    console.log(`Found ${discoveredElements.length} cart elements:`);
    foundSelectors
      .slice(0, 10)
      .forEach((selector) => console.log(`  ✓ ${selector}`));
    if (foundSelectors.length > 10) {
      console.log(`  ... and ${foundSelectors.length - 10} more`);
    }

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
      // Dialog-specific states
      isDialog: element.tagName === "DIALOG",
      wasOpen: element.tagName === "DIALOG" && element.hasAttribute("open"),
      hadScrollLock: element.hasAttribute("scroll-lock"),
      // Class states
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
    console.log("Hiding all cart elements...");

    // Discover all cart elements dynamically
    const elements = discoverCartElements();

    if (elements.length === 0) {
      console.log("No cart elements found to hide");
      return;
    }

    let hiddenCount = 0;

    elements.forEach((element) => {
      if (!element || !document.contains(element)) return;

      // Store original state
      storeElementState(element);

      // Handle dialog elements specially
      if (element.tagName === "DIALOG") {
        try {
          if (element.hasAttribute("open")) {
            element.close();
          }
        } catch (e) {
          console.warn("Failed to close dialog:", e);
        }
      }

      // Apply aggressive hiding
      element.style.display = "none";
      element.style.visibility = "hidden";
      element.style.opacity = "0";
      element.style.pointerEvents = "none";
      element.style.zIndex = "-9999";
      element.style.transform = "translateX(-100vw)";
      element.setAttribute("aria-hidden", "true");
      element.setAttribute("hidden", "true");
      element.removeAttribute("scroll-lock");

      // Remove active classes
      const classesToRemove = [
        "show",
        "active",
        "open",
        "visible",
        "is-open",
        "is-active",
      ];
      classesToRemove.forEach((cls) => element.classList.remove(cls));

      // Add our tracking class
      element.classList.add("codking-hidden");

      hiddenCount++;
    });

    // Remove body scroll lock classes
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
      document.documentElement.classList.remove(cls);
      document.body.classList.remove(cls);
    });

    document.body.style.overflow = "";
    document.documentElement.style.overflow = "";

    // Add comprehensive CSS to ensure EVERYTHING is hidden and non-clickable
    if (!document.getElementById("codking-universal-cart-style")) {
      const style = document.createElement("style");
      style.id = "codking-universal-cart-style";

      // Create CSS rules for all selectors
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
      document.head.appendChild(style);
    }

    console.log(`✅ Successfully hidden ${hiddenCount} cart elements`);
  }

  function restoreDrawer() {
    console.log("Restoring all cart elements...");

    // Remove the hiding CSS first
    const hideStyle = document.getElementById("codking-universal-cart-style");
    if (hideStyle) {
      hideStyle.remove();
    }

    let restoredCount = 0;

    hiddenElementStates.forEach((state, element) => {
      if (!element || !document.contains(element)) return;

      // Restore all style properties
      element.style.display = state.display;
      element.style.visibility = state.visibility;
      element.style.opacity = state.opacity;
      element.style.pointerEvents = state.pointerEvents;
      element.style.zIndex = state.zIndex;
      element.style.transform = state.transform;

      // Restore attributes
      if (state.ariaHidden) {
        element.setAttribute("aria-hidden", state.ariaHidden);
      } else {
        element.removeAttribute("aria-hidden");
      }

      if (!state.hidden) {
        element.removeAttribute("hidden");
      }

      // Handle dialog restoration
      if (state.isDialog) {
        if (state.wasOpen) {
          try {
            element.showModal();
          } catch (e) {
            element.setAttribute("open", "");
          }
        }

        if (state.hadScrollLock) {
          element.setAttribute("scroll-lock", "");
        }
      }

      // Restore classes
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

      // Remove our tracking class
      element.classList.remove("codking-hidden");

      restoredCount++;
    });

    // Clear stored states
    hiddenElementStates.clear();

    console.log(`✅ Successfully restored ${restoredCount} cart elements`);
  }

  // Global function access
  window.codkingHideDrawer = hideDrawer;
  window.codkingRestoreDrawer = restoreDrawer;
  window.codkingDiscoverCarts = discoverCartElements;

  // Event listeners
  window.addEventListener("codking:otpModalOpened", hideDrawer);
  window.addEventListener("codking:otpModalClosed", restoreDrawer);

  // Initial discovery for debugging
  setTimeout(() => {
    discoverCartElements();
  }, 1000);

  console.log("✅ COD King Universal Cart Drawer Manager loaded");
};
// Strategy 2: Color Drawer Specific
export const initializeCartDrawerHidingLogicTwo = () => {
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
    console.log("Strategy 2: Hiding color drawer...");

    let hiddenCount = 0;

    cartDrawerLayouts.forEach((selector) => {
      try {
        const drawers = document.querySelectorAll(selector);
        drawers.forEach((drawer) => {
          if (!drawer || !document.contains(drawer)) return;

          storeDrawerState(drawer);

          if (drawer.tagName === "DIALOG" && drawer.hasAttribute("open")) {
            try {
              drawer.close();
            } catch (e) {
              console.warn("Failed to close color drawer:", e);
            }
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

    if (!document.getElementById("codking-color-drawer-style")) {
      const style = document.createElement("style");
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
          cursor: default !important;
          z-index: -9999 !important;
          transform: translateX(-100vw) !important;
        }
      `;
      document.head.appendChild(style);
    }

    console.log(`Strategy 2: Hidden ${hiddenCount} color drawer elements`);
  }

  function restoreDrawer() {
    console.log("Strategy 2: Restoring color drawer...");

    const hideStyle = document.getElementById("codking-color-drawer-style");
    if (hideStyle) {
      hideStyle.remove();
    }

    let restoredCount = 0;

    colorDrawerStates.forEach((state, drawer) => {
      if (!drawer || !document.contains(drawer)) return;

      drawer.style.display = state.display;
      drawer.style.visibility = state.visibility;
      drawer.style.opacity = state.opacity;
      drawer.style.pointerEvents = "";
      drawer.style.zIndex = state.zIndex;
      drawer.removeAttribute("hidden");
      drawer.classList.remove("codking-hidden");

      if (state.ariaHidden) {
        drawer.setAttribute("aria-hidden", state.ariaHidden);
      } else {
        drawer.removeAttribute("aria-hidden");
      }

      if (drawer.tagName === "DIALOG" && state.wasOpen) {
        try {
          drawer.showModal();
        } catch (e) {
          drawer.setAttribute("open", "");
        }
      }

      if (state.hadScrollLock) {
        drawer.setAttribute("scroll-lock", "");
      }

      restoredCount++;
    });

    colorDrawerStates.clear();
    console.log(`Strategy 2: Restored ${restoredCount} color drawer elements`);
  }

  window.codkingHideDrawer = hideDrawer;
  window.codkingRestoreDrawer = restoreDrawer;
  window.addEventListener("codking:otpModalOpened", hideDrawer);
  window.addEventListener("codking:otpModalClosed", restoreDrawer);

  console.log("Strategy 2: Color Drawer Specific initialized");
  return true;
};

// Strategy 3: Multi Element Drawer
export const initializeCartDrawerHidingLogicThree = () => {
  let cartEls = [];
  let elementStates = new Map();

  function initializeElements() {
    cartEls = [];
    cartDrawerLayouts.forEach((selector) => {
      try {
        const elements = Array.from(document.querySelectorAll(selector));
        if (elements.length > 0) {
          cartEls.push(...elements);
        }
      } catch (e) {
        // Skip invalid selectors
      }
    });

    cartEls = [...new Set(cartEls)];
    return cartEls.length > 0;
  }

  function storeElementState(element) {
    const state = {
      display: element.style.display || "",
      visibility: element.style.visibility || "",
      opacity: element.style.opacity || "",
      pointerEvents: element.style.pointerEvents || "",
      zIndex: element.style.zIndex || "",
      ariaHidden: element.getAttribute("aria-hidden"),
      hidden: element.hasAttribute("hidden"),
      originalDisplay: element.getAttribute("data-codking-display"),
      showClass: element.classList.contains("show"),
      activeClass: element.classList.contains("active"),
      openClass: element.classList.contains("open"),
      visibleClass: element.classList.contains("visible"),
    };
    elementStates.set(element, state);
    return state;
  }

  function hideDrawer() {
    console.log("Strategy 3: Hiding multi-element drawer...");

    if (!cartEls.length && !initializeElements()) {
      console.log("Strategy 3: No drawer elements found");
      return;
    }

    let hiddenCount = 0;

    cartEls.forEach((el) => {
      if (!el || !document.contains(el)) return;

      storeElementState(el);
      el.setAttribute("data-codking-display", el.style.display || "block");

      el.style.display = "none";
      el.style.visibility = "hidden";
      el.style.opacity = "0";
      el.style.pointerEvents = "none";
      el.style.zIndex = "-9999";
      el.setAttribute("aria-hidden", "true");
      el.setAttribute("hidden", "true");

      const classesToRemove = ["show", "active", "open", "visible"];
      classesToRemove.forEach((cls) => el.classList.remove(cls));
      el.classList.add("codking-hidden");

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
    ];

    bodyClasses.forEach((cls) => {
      document.documentElement.classList.remove(cls);
      document.body.classList.remove(cls);
    });

    document.body.style.overflow = "";

    if (!document.getElementById("codking-multi-element-style")) {
      const style = document.createElement("style");
      style.id = "codking-multi-element-style";

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
      document.head.appendChild(style);
    }

    console.log(`Strategy 3: Hidden ${hiddenCount} drawer elements`);
  }

  function restoreDrawer() {
    console.log("Strategy 3: Restoring multi-element drawer...");

    const hideStyle = document.getElementById("codking-multi-element-style");
    if (hideStyle) {
      hideStyle.remove();
    }

    let restoredCount = 0;

    elementStates.forEach((state, el) => {
      if (!el || !document.contains(el)) return;

      el.style.display =
        el.getAttribute("data-codking-display") || state.display || "block";
      el.style.visibility = state.visibility;
      el.style.opacity = state.opacity;
      el.style.pointerEvents = "auto";
      el.style.zIndex = state.zIndex;
      el.removeAttribute("hidden");

      if (state.ariaHidden) {
        el.setAttribute("aria-hidden", state.ariaHidden);
      } else {
        el.removeAttribute("aria-hidden");
      }

      const classStates = {
        show: state.showClass,
        active: state.activeClass,
        open: state.openClass,
        visible: state.visibleClass,
      };

      Object.entries(classStates).forEach(([className, shouldHave]) => {
        if (shouldHave) {
          el.classList.add(className);
        }
      });

      el.classList.remove("codking-hidden");
      el.removeAttribute("data-codking-display");
      restoredCount++;
    });

    elementStates.clear();
    console.log(`Strategy 3: Restored ${restoredCount} drawer elements`);
  }

  if (!initializeElements()) {
    console.log("Strategy 3: No elements found, strategy not viable");
    return false;
  }

  window.codkingHideDrawer = hideDrawer;
  window.codkingRestoreDrawer = restoreDrawer;
  window.addEventListener("codking:otpModalOpened", hideDrawer);
  window.addEventListener("codking:otpModalClosed", restoreDrawer);

  console.log("Strategy 3: Multi Element Drawer initialized");
  return true;
};

// Strategy 4: Simple Offcanvas
export const initializeCartDrawerHidingLogicFour = () => {
  let cartElements = [];
  let elementStates = new Map();

  function findCartElements() {
    cartElements = [];
    cartDrawerLayouts.forEach((selector) => {
      try {
        const elements = document.querySelectorAll(selector);
        if (elements.length > 0) {
          cartElements.push(...Array.from(elements));
        }
      } catch (e) {
        // Skip invalid selector
      }
    });

    cartElements = [...new Set(cartElements)];
    return cartElements.length > 0;
  }

  function storeElementState(element) {
    const state = {
      display: element.style.display || "",
      visibility: element.style.visibility || "",
      opacity: element.style.opacity || "",
      pointerEvents: element.style.pointerEvents || "",
      zIndex: element.style.zIndex || "",
      ariaHidden: element.getAttribute("aria-hidden"),
      hidden: element.hasAttribute("hidden"),
      originalDisplay: element.getAttribute("data-codking-display"),
      showClass: element.classList.contains("show"),
      activeClass: element.classList.contains("active"),
      openClass: element.classList.contains("open"),
      visibleClass: element.classList.contains("visible"),
    };
    elementStates.set(element, state);
    return state;
  }

  function hideDrawer() {
    console.log("Strategy 4: Hiding simple offcanvas cart...");

    if (!cartElements.length && !findCartElements()) {
      console.log("Strategy 4: No offcanvas cart elements found");
      return;
    }

    let hiddenCount = 0;

    cartElements.forEach((cartEl) => {
      if (!cartEl || !document.contains(cartEl)) return;

      storeElementState(cartEl);
      cartEl.setAttribute(
        "data-codking-display",
        cartEl.style.display || "block"
      );

      cartEl.style.display = "none";
      cartEl.style.visibility = "hidden";
      cartEl.style.opacity = "0";
      cartEl.style.pointerEvents = "none";
      cartEl.style.zIndex = "-9999";
      cartEl.setAttribute("aria-hidden", "true");
      cartEl.setAttribute("hidden", "true");

      const classesToRemove = ["show", "active", "open", "visible"];
      classesToRemove.forEach((cls) => cartEl.classList.remove(cls));
      cartEl.classList.add("codking-hidden");

      hiddenCount++;
    });

    document.body.classList.remove("scroll-lock", "no-scroll", "cart-open");
    document.body.style.overflow = "";

    if (!document.getElementById("codking-simple-offcanvas-style")) {
      const style = document.createElement("style");
      style.id = "codking-simple-offcanvas-style";

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
      document.head.appendChild(style);
    }

    console.log(`Strategy 4: Hidden ${hiddenCount} offcanvas cart elements`);
  }

  function restoreDrawer() {
    console.log("Strategy 4: Restoring simple offcanvas cart...");

    const hideStyle = document.getElementById("codking-simple-offcanvas-style");
    if (hideStyle) {
      hideStyle.remove();
    }

    let restoredCount = 0;

    elementStates.forEach((state, cartEl) => {
      if (!cartEl || !document.contains(cartEl)) return;

      cartEl.style.display =
        cartEl.getAttribute("data-codking-display") || state.display || "block";
      cartEl.style.visibility = state.visibility;
      cartEl.style.opacity = state.opacity;
      cartEl.style.pointerEvents = "auto";
      cartEl.style.zIndex = state.zIndex;
      cartEl.removeAttribute("hidden");

      if (state.ariaHidden) {
        cartEl.setAttribute("aria-hidden", state.ariaHidden);
      } else {
        cartEl.removeAttribute("aria-hidden");
      }

      const classStates = {
        show: state.showClass,
        active: state.activeClass,
        open: state.openClass,
        visible: state.visibleClass,
      };

      Object.entries(classStates).forEach(([className, shouldHave]) => {
        if (shouldHave) {
          cartEl.classList.add(className);
        }
      });

      cartEl.classList.remove("codking-hidden");
      cartEl.removeAttribute("data-codking-display");
      restoredCount++;
    });

    elementStates.clear();
    console.log(
      `Strategy 4: Restored ${restoredCount} offcanvas cart elements`
    );
  }

  if (!findCartElements()) {
    console.log("Strategy 4: No offcanvas elements found, strategy not viable");
    return false;
  }

  window.codkingHideDrawer = hideDrawer;
  window.codkingRestoreDrawer = restoreDrawer;
  window.addEventListener("codking:otpModalOpened", hideDrawer);
  window.addEventListener("codking:otpModalClosed", restoreDrawer);

  console.log("Strategy 4: Simple Offcanvas initialized");
  return true;
};

export const initializeCartDrawerHidingLogicFive = () => {
  // No need for a Map since your original code uses data-* attributes on the element itself
  function hideDrawer() {
    console.log("Strategy 5: Hiding dialog cart drawer...");

    // First, try the hardcoded dialog selector (priority)
    const dialog = document.querySelector("dialog.cart-drawer__dialog");
    let hiddenCount = 0;

    if (dialog) {
      console.log("Found cart dialog:", dialog);
      hideDialog(dialog);
      hiddenCount++;
    } else {
      console.log(
        "No dialog.cart-drawer__dialog found. Falling back to cartDrawerLayouts..."
      );
      // Fallback: Search cartDrawerLayouts for dialogs
      cartDrawerLayouts.forEach((selector) => {
        try {
          const elements = document.querySelectorAll(selector);
          elements.forEach((el) => {
            if (
              el.tagName === "DIALOG" &&
              !el.classList.contains("codking-hidden")
            ) {
              hideDialog(el);
              hiddenCount++;
            }
          });
        } catch (e) {
          console.warn(`Invalid selector: ${selector}`, e);
        }
      });
    }

    if (hiddenCount === 0) {
      console.log("Strategy 5: No dialog cart elements found to hide.");
      return;
    }

    // Add comprehensive CSS (exact match to your original)
    if (!document.getElementById("codking-dialog-cart-style")) {
      const style = document.createElement("style");
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
      document.head.appendChild(style);
    }

    console.log(`✅ Strategy 5: Hidden ${hiddenCount} dialog cart element(s)`);
  }

  // Exact copy of your hideDialog logic
  function hideDialog(dialog) {
    // Store original state (using data-* attributes, as in your original)
    dialog.setAttribute(
      "data-codking-was-open",
      dialog.hasAttribute("open") ? "true" : "false"
    );
    dialog.setAttribute(
      "data-codking-had-scroll-lock",
      dialog.hasAttribute("scroll-lock") ? "true" : "false"
    );
    dialog.setAttribute("data-codking-display", dialog.style.display || "");

    // Close the dialog properly
    if (dialog.hasAttribute("open")) {
      dialog.close();
    }

    // Apply aggressive hiding (exact match to your original)
    dialog.style.display = "none";
    dialog.style.visibility = "hidden";
    dialog.style.opacity = "0";
    dialog.style.pointerEvents = "none";
    dialog.style.zIndex = "-9999";
    dialog.setAttribute("aria-hidden", "true");
    dialog.setAttribute("hidden", "true");
    dialog.removeAttribute("scroll-lock");

    // Hide inner content (exact selectors from your original)
    const innerElements = dialog.querySelectorAll(
      ".cart-drawer__inner, cart-items-component, .cart-items-component"
    );
    innerElements.forEach((el) => {
      el.style.display = "none";
      el.style.pointerEvents = "none";
      el.setAttribute("aria-hidden", "true");
    });

    // Remove scroll lock from body (exact match)
    document.body.classList.remove("scroll-lock", "no-scroll");
    document.body.style.overflow = "";
  }

  function restoreDrawer() {
    console.log("Strategy 5: Restoring dialog cart drawer...");

    // Remove the hiding CSS
    const hideStyle = document.getElementById("codking-dialog-cart-style");
    if (hideStyle) {
      hideStyle.remove();
    }

    // Restore the dialog (exact logic from your original)
    const dialog = document.querySelector("dialog.cart-drawer__dialog");
    if (!dialog) {
      console.log(
        "Cart dialog not found for restoration. Checking cartDrawerLayouts..."
      );
      // Fallback: Search cartDrawerLayouts for dialogs to restore
      let restoredCount = 0;
      cartDrawerLayouts.forEach((selector) => {
        try {
          const elements = document.querySelectorAll(selector);
          elements.forEach((el) => {
            if (
              el.tagName === "DIALOG" &&
              el.hasAttribute("data-codking-was-open")
            ) {
              restoreDialog(el);
              restoredCount++;
            }
          });
        } catch (e) {
          console.warn(`Invalid selector: ${selector}`, e);
        }
      });
      if (restoredCount === 0) {
        console.log("Strategy 5: No dialog cart elements found to restore.");
      } else {
        console.log(
          `✅ Strategy 5: Restored ${restoredCount} dialog cart element(s)`
        );
      }
      return;
    }

    // Restore the dialog (exact match to your original)
    dialog.style.display = dialog.getAttribute("data-codking-display") || "";
    dialog.style.visibility = "";
    dialog.style.opacity = "";
    dialog.style.pointerEvents = "";
    dialog.style.zIndex = "";
    dialog.removeAttribute("aria-hidden");
    dialog.removeAttribute("hidden");

    // Restore dialog state
    const wasOpen = dialog.getAttribute("data-codking-was-open") === "true";
    const hadScrollLock =
      dialog.getAttribute("data-codking-had-scroll-lock") === "true";

    if (wasOpen) {
      try {
        dialog.showModal();
      } catch (e) {
        dialog.setAttribute("open", "");
      }
    }

    if (hadScrollLock) {
      dialog.setAttribute("scroll-lock", "");
    }

    // Restore inner elements (exact selectors)
    const innerElements = dialog.querySelectorAll(
      ".cart-drawer__inner, cart-items-component, .cart-items-component"
    );
    innerElements.forEach((el) => {
      el.style.display = "";
      el.style.pointerEvents = "";
      el.removeAttribute("aria-hidden");
    });

    // Clean up tracking attributes (exact match)
    dialog.removeAttribute("data-codking-was-open");
    dialog.removeAttribute("data-codking-had-scroll-lock");
    dialog.removeAttribute("data-codking-display");

    console.log("✅ Strategy 5: Cart dialog restored successfully");
  }

  // Helper function to restore dialogs found via cartDrawerLayouts
  function restoreDialog(dialog) {
    dialog.style.display = dialog.getAttribute("data-codking-display") || "";
    dialog.style.visibility = "";
    dialog.style.opacity = "";
    dialog.style.pointerEvents = "";
    dialog.style.zIndex = "";
    dialog.removeAttribute("aria-hidden");
    dialog.removeAttribute("hidden");

    const wasOpen = dialog.getAttribute("data-codking-was-open") === "true";
    const hadScrollLock =
      dialog.getAttribute("data-codking-had-scroll-lock") === "true";

    if (wasOpen) {
      try {
        dialog.showModal();
      } catch (e) {
        dialog.setAttribute("open", "");
      }
    }

    if (hadScrollLock) {
      dialog.setAttribute("scroll-lock", "");
    }

    const innerElements = dialog.querySelectorAll(
      ".cart-drawer__inner, cart-items-component, .cart-items-component"
    );
    innerElements.forEach((el) => {
      el.style.display = "";
      el.style.pointerEvents = "";
      el.removeAttribute("aria-hidden");
    });

    dialog.removeAttribute("data-codking-was-open");
    dialog.removeAttribute("data-codking-had-scroll-lock");
    dialog.removeAttribute("data-codking-display");
  }

  // Initialize
  window.codkingHideDrawer = hideDrawer;
  window.codkingRestoreDrawer = restoreDrawer;
  window.addEventListener("codking:otpModalOpened", hideDrawer);
  window.addEventListener("codking:otpModalClosed", restoreDrawer);

  console.log(
    "✅ Strategy 5: Dialog-Specific Cart Drawer initialized (exact match + fallback)"
  );
  return true;
};
