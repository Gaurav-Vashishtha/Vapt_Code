import React, { useEffect, useState } from "react";

import {
  CART_DRAWER_LAYOUT,
  EXCEPTION_STORES,
  SELECTORS,
} from "../utilities/selectors.js";
import {
  injectCustomCode,
  checkAndAddBuyNow,
  forceZIndex,
} from "../services/domUtils.js";
import {
  getCurrentStep,
  getLocalValue,
  getSessionValue,
  setSessionValue,
} from "../utilities/otpUtils.js";
import { hideSpinner } from "../utilities/spinner.js";
import useOtpStore from "../stores/otpStore.js";
import { shopifyAddToCartForBuyNow } from "../services/cartService.js";
import { sendErrorToAPI } from "../services/errorReporter.js";
import ModalContainer from "./ModalContainer.js";
import OTPWidget from "./OTPWidget.js";

// discount summary is handled inside DesktopOrderSummary

const ButtonManager = () => {
  const session = getSessionValue("verifiedNumberData");
  const settings = getSessionValue("settingSession");
  const [showModal, setShowModal] = useState(false);

  // Safely destructure settings with fallbacks
  const {
    isNewDesignEnabled = false,
    preIsLoginEnabled = false,
    preGeoCountries = null,
    partialPaymentEnabled = false,
    preV2CartDrawerLayoutSelectors,
  } = settings || {};

  const isOtpVerified = !!(session && session.isOTPVerified); //This uses the double negation (!!) to convert any falsy value (including null and undefined) to false. If session.isOTPVerified is truthy, it will remain true
  const {
    setStep,
    showOTPModal,
    setShowOTPModal,
    setIsCartReady,
    setIsBuyNowReady,
    resetCurrentCartData,
    resetOrderSummary,
  } = useOtpStore();

  const allowedCountries = preGeoCountries; // or "all"
  const isPartialEnabled = partialPaymentEnabled;
  const defaultCountry = getLocalValue("defaultCountry");

  const isAllowedCountry = () => {
    if (!allowedCountries) return true;
    if (defaultCountry === "") return true;

    const allowedList = allowedCountries
      .split(",")
      .map((c) => c.trim().toLowerCase());

    const countryCode =
      typeof defaultCountry === "string"
        ? defaultCountry.toLowerCase()
        : Array.isArray(defaultCountry)
          ? defaultCountry[0]?.toLowerCase()
          : null;

    return countryCode && allowedList.includes(countryCode);
  };

  const openModal = async () => {
    try {
      setSessionValue("partial_payment_cart_results", null);

      if (window.codkModalState === "open") {
        return false;
      }

      // The COD form embed marks the page while its form owns the cart drawer: then this popup
      // leaves the drawer alone (only one popup condition runs at a time).
      window.codkDrawerSkipped = document.documentElement.hasAttribute("data-codkf-drawer");
      if (!window.codkDrawerSkipped) window.dispatchEvent(new Event("codking:otpModalOpened"));
      window.codkModalState = "open";
      setIsCartReady(false);
      setIsBuyNowReady(false);
      // Reset currentCartData and orderSummary to null on every popup open to ensure fresh data is fetched
      resetCurrentCartData();
      resetOrderSummary();
      setShowModal(true);
      setShowOTPModal(true);
      forceZIndex();

      return true;
    } catch (error) {
      console.error("❌ openModal failed:", error);

      const errorContext = collectErrorContext(error, "openModal");

      sendErrorToAPI(error, "openModal").catch((err) => {
        console.warn("Failed to send openModal error to API:", err);
      });

      window.dispatchEvent(
        new CustomEvent("codking:openModalFailure", {
          detail: errorContext,
        }),
      );

      if (window.CODKingErrorReporter) {
        window.CODKingErrorReporter.reportError(errorContext);
      }

      return false;
    }
  };

  // Function to close the modal
  const closeModal = () => {
    try {
      if (!window.codkDrawerSkipped) window.dispatchEvent(new Event("codking:otpModalClosed"));
      window.codkDrawerSkipped = false;
      window.codkModalState = "closed";
      setShowModal(false);
      setShowOTPModal(false);
    } catch (error) {
      console.error("❌ closeModal failed:", error);
    }
  };
  window.closeModal = closeModal;

  const handleBlockButton = (e) => {
    e.preventDefault();
    e.stopPropagation();
  };

  // Function to attach event listeners to buttons
  const attachEventListeners = (button) => {
    try {
      if (!button.hasAttribute("data-event-listener-attached")) {
        button.addEventListener(
          "click",
          window.CODKingBlockEventListener,
          true,
        );
        button.addEventListener("click", window.popupEventListener, true);
        button.setAttribute("data-event-listener-attached", "true");
        return true;
      }
      return true;
    } catch (error) {
      console.error("❌ attachEventListeners failed:", error);
      return false;
    }
  };

  const removeEventListeners = () => {
    try {
      Object.keys(SELECTORS).forEach((key) => {
        const selectors = SELECTORS[key];
        selectors.forEach((selector) => {
          document.querySelectorAll(selector).forEach((button) => {
            button.removeEventListener(
              "click",
              window.CODKingBlockEventListener,
              true,
            );
            button.removeEventListener(
              "click",
              window.popupEventListener,
              true,
            );
            button.removeAttribute("data-event-listener-attached");
          });
        });
      });
    } catch (error) {
      console.error("❌ removeEventListeners failed:", error);
    }
  };

  // const observeBuyNowButton = () => {
  //   try {
  //     const buttons = document.querySelectorAll(SELECTORS.BUY_NOW.join(","));

  //     if (buttons.length === 0) {
  //       return false;
  //     }

  //     buttons.forEach((button) => {
  //       if (!button.hasAttribute("data-event-listener-attached")) {
  //         button.addEventListener("click", shopifyAddToCartForBuyNow, true);
  //         button.setAttribute("data-event-listener-attached", "true");
  //       }
  //     });

  //     return true;
  //   } catch (error) {
  //     console.error("❌ observeBuyNowButton failed:", error);
  //     return false;
  //   }
  // };

  const removeExisitingListeners = () => {
    try {
      const cartDrawerSelectors = SELECTORS.CART_DRAWER;
      cartDrawerSelectors.forEach((selector) => {
        document.querySelectorAll(selector).forEach((button) => {
          button.removeAttribute("onclick");
          button.removeAttribute("href");
        });
      });
    } catch (error) {
      console.error("❌ removeExisitingListeners failed:", error);
    }
  };

  const checkExceptioStore = () => {
    try {
      if (EXCEPTION_STORES.includes(window.Shopify.shop) === true) {
        removeExisitingListeners();
        return true;
      }
      return false;
    } catch (error) {
      console.error("❌ checkExceptioStore failed:", error);
      return false;
    }
  };

  // Enhanced error context collection and API reporting
  const collectErrorContext = (error, operation = "unknown") => {
    const context = {
      // Error Details
      error: {
        message: error.message,
        stack: error.stack,
        name: error.name,
        toString: error.toString(),
      },

      // Device & Browser Info
      device: {
        userAgent: navigator.userAgent,
        platform: navigator.platform,
        vendor: navigator.vendor || "unknown",
        language: navigator.language,
        languages: navigator.languages || [],
        onLine: navigator.onLine,
        cookieEnabled: navigator.cookieEnabled,
        doNotTrack: navigator.doNotTrack || "unknown",
      },

      // Screen & Viewport
      screen: {
        width: screen.width,
        height: screen.height,
        availWidth: screen.availWidth,
        availHeight: screen.availHeight,
        colorDepth: screen.colorDepth,
        pixelDepth: screen.pixelDepth,
        orientation: screen.orientation?.type || "unknown",
      },

      // Window & Document
      window: {
        innerWidth: window.innerWidth,
        innerHeight: window.innerHeight,
        outerWidth: window.outerWidth,
        outerHeight: window.outerHeight,
        devicePixelRatio: window.devicePixelRatio,
        scrollX: window.scrollX,
        scrollY: window.scrollY,
      },

      // Page Context
      page: {
        url: window.location.href,
        pathname: window.location.pathname,
        search: window.location.search,
        hash: window.location.hash,
        referrer: document.referrer,
        title: document.title,
        readyState: document.readyState,
        visibilityState: document.visibilityState,
      },

      // Shopify Context
      shopify: {
        shop: window.Shopify?.shop || "unknown",
        currency: window.Shopify?.currency || "unknown",
        country: window.Shopify?.country || "unknown",
        locale: window.Shopify?.locale || "unknown",
        theme: window.Shopify?.theme || {},
        checkout: window.Shopify?.checkout || {},
      },

      // COD King Context
      codking: {
        modalState: window.codkModalState || "unknown",
        session: getSessionValue("verifiedNumberData"),
        settings: getSessionValue("settingSession"),
        defaultCountry: getLocalValue("defaultCountry"),
        machineId: getSessionValue("MachineId"),
      },

      // React State
      reactState: {
        showModal,
        showOTPModal,
        isOtpVerified,
        isPartialEnabled,
        allowedCountries,
        preIsLoginEnabled,
      },

      // DOM Context
      dom: {
        readyState: document.readyState,
        activeElement: document.activeElement?.tagName || "unknown",
        body: !!document.body,
        head: !!document.head,
        elementsCount: document.querySelectorAll("*").length,
      },

      // Performance & Memory
      performance: {
        now: performance.now(),
        timeOrigin: performance.timeOrigin,
        memory: performance.memory
          ? {
              usedJSHeapSize: performance.memory.usedJSHeapSize,
              totalJSHeapSize: performance.memory.totalJSHeapSize,
              jsHeapSizeLimit: performance.memory.jsHeapSizeLimit,
            }
          : "unavailable",
      },

      // Network
      connection: navigator.connection
        ? {
            effectiveType: navigator.connection.effectiveType,
            downlink: navigator.connection.downlink,
            rtt: navigator.connection.rtt,
            saveData: navigator.connection.saveData,
          }
        : "unavailable",

      // Timestamp
      timestamp: new Date().toISOString(),
      operation,
    };

    return context;
  };

  // Send error to COD King API using otpService
  // Send error to COD King API using otpService

  const popupEventListener = (e) => {
    try {
      if (!e.currentTarget) {
        throw new Error("Event currentTarget is null or undefined");
      }

      checkAndAddBuyNow(e.currentTarget);
      injectCustomCode(openModal);
    } catch (error) {
      console.error("❌ popupEventListener failed:", error);

      const errorContext = collectErrorContext(error, "popupEventListener");
      errorContext.buttonElement = {
        tagName: e.currentTarget?.tagName || "unknown",
        className: e.currentTarget?.className || "",
        id: e.currentTarget?.id || "",
        text: e.currentTarget?.textContent?.substring(0, 50) || "",
      };

      sendErrorToAPI(errorContext, "critical").catch((err) => {
        console.warn("Failed to send error to API:", err);
      });

      try {
        if (showModal !== true) {
          setShowModal(true);
          setShowOTPModal(true);
        }
      } catch (fallbackError) {
        console.error("❌ Fallback also failed:", fallbackError);

        const fallbackErrorContext = collectErrorContext(
          fallbackError,
          "popupEventListener_fallback",
        );

        sendErrorToAPI(fallbackErrorContext, "critical").catch((err) => {
          console.warn("Failed to send fallback error to API:", err);
        });
      }
    }
  };
  if (window.CODKingBlockEventListener == undefined) {
    window.CODKingBlockEventListener = handleBlockButton;
  }
  //defining otpVerification fucntions as a window object
  window.popupEventListener = popupEventListener;

  const observeButtons = () => {
    try {
      Object.keys(SELECTORS).forEach((key) => {
        const selectors = SELECTORS[key];
        selectors.forEach((selector) => {
          document.querySelectorAll(selector).forEach((button) => {
            if (!button.disabled) {
              selector == "CART_DRAWER" && checkExceptioStore();
              attachEventListeners(button);
              hideSpinner();
            } else {
              const observer = new MutationObserver(
                (mutationsList, observer) => {
                  try {
                    mutationsList.forEach((mutation) => {
                      if (
                        mutation.attributeName === "disabled" &&
                        !button.disabled
                      ) {
                        selector == "CART_DRAWER" && checkExceptioStore();
                        attachEventListeners(button);
                        observer.disconnect();
                        hideSpinner();
                      } else if (
                        mutation.attributeName === "open" &&
                        button.hasAttribute("open")
                      ) {
                        attachEventListeners(button);
                        observer.disconnect();
                        hideSpinner();
                      }
                    });
                  } catch (observerError) {
                    console.error(
                      "❌ MutationObserver callback failed:",
                      observerError,
                    );
                    observer.disconnect();
                  }
                },
              );
              observer.observe(button, { attributes: true });
            }
          });
        });
      });
    } catch (error) {
      console.error("❌ observeButtons failed:", error);
    }
  };

  const observeCartDrawer = () => {
    try {
      const cartDrawerLayouts = preV2CartDrawerLayoutSelectors
        ? CART_DRAWER_LAYOUT.concat(
            preV2CartDrawerLayoutSelectors
              .split(",")
              .map((s) => s.trim())
              .filter(Boolean),
          )
        : CART_DRAWER_LAYOUT;
      cartDrawerLayouts.forEach((selector) => {
        const cartDrawer = document.querySelector(selector);
        if (cartDrawer) {
          const observer = new MutationObserver(() => {
            try {
              observeButtons();
            } catch (error) {
              console.error("❌ Cart drawer observer callback failed:", error);
            }
          });
          observer.observe(cartDrawer, { childList: true, subtree: true });
        }
      });
    } catch (error) {
      console.error("❌ observeCartDrawer failed:", error);
    }
  };

  const saveSessionIdAsMachideIdFromParam = () => {
    try {
      if (typeof window !== "undefined") {
        const urlParams = new URLSearchParams(window.location.search);
        const codkSessionId = urlParams.get("_codkSessionId");

        if (codkSessionId) {
          setSessionValue("MachineId", codkSessionId);
        }
      }
    } catch (error) {
      console.error("❌ saveSessionIdAsMachideIdFromParam failed:", error);
    }
  };

  const setupCODKWidget = async () => {
    try {
      saveSessionIdAsMachideIdFromParam();

      if (!isAllowedCountry()) {
        return false;
      }

      if (settings?.preIsLoginEnabled) {
        removeEventListeners();
        // observeBuyNowButton();
        return true;
      }

      observeButtons();
      observeCartDrawer();
      const currentStep = await getCurrentStep();
      setStep(currentStep);

      return true;
    } catch (error) {
      console.error("❌ setupCODKWidget failed:", error);

      const errorContext = collectErrorContext(error, "setupCODKWidget");

      sendErrorToAPI(errorContext, "error").catch((err) => {
        console.warn("Failed to send setup error to API:", err);
      });

      window.dispatchEvent(
        new CustomEvent("codking:setupFailure", {
          detail: errorContext,
        }),
      );

      if (window.CODKingErrorReporter) {
        window.CODKingErrorReporter.reportError(errorContext);
      }

      return false;
    }
  };

  useEffect(() => {
    const init = async () => {
      try {
        await setupCODKWidget();
        // CartRevertService();
        // CartRevertServiceRaw();
      } catch (error) {
        console.error("❌ ButtonManager useEffect failed:", error);

        const errorContext = collectErrorContext(
          error,
          "useEffect_initialization",
        );

        sendErrorToAPI(errorContext, "error").catch((err) => {
          console.warn("Failed to send useEffect error to API:", err);
        });

        window.dispatchEvent(
          new CustomEvent("codking:initializationFailure", {
            detail: errorContext,
          }),
        );

        if (window.CODKingErrorReporter) {
          window.CODKingErrorReporter.reportError(errorContext);
        }
      }
    };

    init();
  }, []);

  return (
    <>
      {showModal && (
        <ModalContainer onClose={closeModal}>
          <OTPWidget onClose={closeModal} />
        </ModalContainer>
      )}
    </>
  );
};

export default ButtonManager;
