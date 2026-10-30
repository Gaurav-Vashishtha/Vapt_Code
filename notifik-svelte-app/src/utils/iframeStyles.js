/**
 * Iframe Styles Utility
 * Handles injection of CSS styles into parent window for iframe modal
 */

const WRAPPER_ID = "codk-modal-wrapper";
const IFRAME_ID = "codk-full-modal-svelte";
const STYLE_ELEMENT_ID = "codk-iframe-styles";

/**
 * Get the CSS styles for the iframe modal wrapper and iframe
 * @returns {string} CSS styles as a string
 */
export const getIframeStyles = () => {
  return `
    /* COD King Svelte App - Modal Wrapper and Iframe Styles (GoKwik-like structure) */

    /* Modal Wrapper - Like GoKwik's gokwik-modalwrapper */
    /* Wrapper is just a container - never captures events, only iframe does */
    #${WRAPPER_ID} {
      width: 100% !important;
      height: 100% !important;
      z-index: 2147483647 !important;
      top: 0 !important;
      left: 0 !important;
      right: 0 !important;
      bottom: 0 !important;
      position: fixed !important;
      pointer-events: none !important;
      visibility: hidden !important;
      opacity: 0 !important;
    }

    #${WRAPPER_ID}[data-visible="true"] {
      visibility: visible !important;
      opacity: 1 !important;
    }

    #${WRAPPER_ID}[data-visible="false"] {
      pointer-events: none !important;
      visibility: hidden !important;
      opacity: 0 !important;
      z-index: -9999 !important;
    }

    /* Iframe - ALWAYS full-screen */
    #${IFRAME_ID} {
      position: fixed !important;
      top: 0px !important;
      bottom: 0px !important;
      right: 0px !important;
      left: 0px !important;
      width: 100% !important;
      border: none !important;
      margin: 0 !important;
      padding: 0 !important;
      overflow: hidden !important;
      z-index: 2147483647 !important;
      height: 100% !important;
      background: transparent !important;
      pointer-events: none !important;
      visibility: hidden !important;
      opacity: 0 !important;
    }

    /* Mobile and Desktop: Iframe is always full-screen */
    #${WRAPPER_ID}[data-visible="true"] {
      display: block !important;
    }

    #${IFRAME_ID}[data-visible="true"] {
      pointer-events: auto !important;
      visibility: visible !important;
      opacity: 1 !important;
    }

    /* When hidden */
    #${WRAPPER_ID}[data-visible="false"],
    #${IFRAME_ID}[data-visible="false"] {
      pointer-events: none !important;
      visibility: hidden !important;
      opacity: 0 !important;
    }
  `;
};

/**
 * Inject iframe CSS into parent window
 * This function should be called when the app initializes
 */
export const injectIframeStyles = () => {
  if (
    typeof window === "undefined" ||
    !window.parent ||
    window.parent === window
  ) {
    return;
  }

  try {
    const parentDoc = window.parent.document;

    // Check if style already exists
    let styleElement = parentDoc.getElementById(STYLE_ELEMENT_ID);

    if (!styleElement) {
      styleElement = parentDoc.createElement("style");
      styleElement.id = STYLE_ELEMENT_ID;
      styleElement.textContent = getIframeStyles();
      parentDoc.head.appendChild(styleElement);
    }
  } catch (e) {

  }
};

/**
 * Setup visual viewport height tracking to account for browser UI (address bar)
 * Updates CSS custom property --visual-viewport-height on the document root
 * @returns {Function} Cleanup function to remove event listeners
 */
export const setupVisualViewportHeight = () => {
  const updateVisualViewportHeight = () => {
    if (typeof window !== "undefined" && typeof document !== "undefined") {
      const viewport = window.visualViewport;
      const rawHeight = viewport ? viewport.height : window.innerHeight;
      const height = Math.floor(rawHeight / 2) * 2;
      document.documentElement.style.setProperty(
        "--visual-viewport-height",
        `${height}px`
      );
    }
  };

  // Set initial height
  updateVisualViewportHeight();

  // Listen for viewport changes (address bar show/hide)
  if (typeof window !== "undefined" && window.visualViewport) {
    window.visualViewport.addEventListener(
      "resize",
      updateVisualViewportHeight
    );
    window.visualViewport.addEventListener(
      "scroll",
      updateVisualViewportHeight
    );
  }
  // Also listen to window resize as fallback
  if (typeof window !== "undefined") {
    window.addEventListener("resize", updateVisualViewportHeight);
  }

  // Return cleanup function
  return () => {
    if (typeof window !== "undefined") {
      if (window.visualViewport) {
        window.visualViewport.removeEventListener(
          "resize",
          updateVisualViewportHeight
        );
        window.visualViewport.removeEventListener(
          "scroll",
          updateVisualViewportHeight
        );
      }
      window.removeEventListener("resize", updateVisualViewportHeight);
    }
  };
};

/**
 * Setup mobile viewport and touch event handlers
 * Prevents zoom, pull-to-refresh, and double-tap zoom
 * @returns {Function} Cleanup function to remove event listeners
 */
export const setupMobileViewportHandlers = () => {
  // Prevent zoom on input focus (iOS Safari)
  const preventZoom = (e) => {
    if (
      e.target.tagName === "INPUT" ||
      e.target.tagName === "TEXTAREA" ||
      e.target.tagName === "SELECT"
    ) {
      const viewport = document.querySelector('meta[name="viewport"]');
      if (viewport) {
        viewport.setAttribute(
          "content",
          "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover"
        );
      }
    }
  };

  // Prevent pull-to-refresh (overscroll) without blocking scrollable areas
  let lastTouchY = 0;
  const isScrollable = (el) => {
    let node = el;
    while (node && node !== document.body) {
      const style = window.getComputedStyle(node);
      const overflowY = style.getPropertyValue("overflow-y");
      const canScroll =
        (overflowY === "auto" || overflowY === "scroll") &&
        node.scrollHeight > node.clientHeight + 1;
      if (canScroll) return true;
      node = node.parentElement;
    }
    return false;
  };

  const preventPullToRefresh = (e) => {
    // Allow scroll within any scrollable ancestor (e.g., address list)
    if (isScrollable(e.target)) return;

    const touchY = e.touches[0].clientY;
    const scrollTop =
      document.documentElement.scrollTop || document.body.scrollTop;

    // If user is at the top and trying to scroll down, prevent default
    if (scrollTop === 0 && touchY > lastTouchY) {
      e.preventDefault();
    }
    lastTouchY = touchY;
  };

  // Prevent double-tap zoom
  let lastTap = 0;
  const preventDoubleTapZoom = (e) => {
    const currentTime = new Date().getTime();
    const tapLength = currentTime - lastTap;
    if (tapLength < 300 && tapLength > 0) {
      e.preventDefault();
    }
    lastTap = currentTime;
  };

  // Restore viewport after input blur
  const restoreViewport = () => {
    const viewport = document.querySelector('meta[name="viewport"]');
    if (viewport) {
      viewport.setAttribute(
        "content",
        "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover"
      );
    }
  };

  // Add event listeners
  document.addEventListener("touchstart", preventZoom, { passive: false });
  document.addEventListener("touchmove", preventPullToRefresh, {
    passive: false,
  });
  document.addEventListener("touchend", preventDoubleTapZoom, {
    passive: false,
  });
  document.addEventListener("blur", restoreViewport, true);

  // Return cleanup function
  return () => {
    document.removeEventListener("touchstart", preventZoom);
    document.removeEventListener("touchmove", preventPullToRefresh);
    document.removeEventListener("touchend", preventDoubleTapZoom);
    document.removeEventListener("blur", restoreViewport, true);
  };
};

/**
 * Setup bfcache (back/forward cache) restoration handler
 * When page is restored from bfcache, performs cart cleanup
 * @param {Function} cleanupCartOnLoad - Function to call for cart cleanup
 * @returns {() => void} Cleanup function to remove event listener
 */
export const setupBfcacheHandler = (cleanupCartOnLoad) => {
  const handlePageShow = async (event) => {
    if (event.persisted) {
      try {
        await cleanupCartOnLoad(true); // true = bfcache restoration
      } catch (error) {
        // Fail silently - don't block anything
      }
    }
  };

  window.addEventListener("pageshow", handlePageShow);

  // Return cleanup function
  return () => {
    window.removeEventListener("pageshow", handlePageShow);
  };
};
