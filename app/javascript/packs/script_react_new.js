import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import OTPManager from "./Modal/components/OTPManager";
import OTPManagerWrapper from "./Modal/components/OTPManagerWrapper";
import { debugLog } from "./Modal/utilities/otpUtils";

const isCheckoutOrOrderPage = () => {
  const url = window.location.href;

  // Match exact "checkouts" or "orders" in the pathname, not as a query parameter
  const pathCheck = url.match(/\/checkouts\b|\/orders\b/);

  // Ensure it's not part of a query string
  const queryCheck =
    url.includes("checkout_url=") || url.includes("orders_url=");

  return pathCheck && !queryCheck;
};

const InitAppScript = () => {
  if (!window.COD_KING_INITIALIZED) {
    window.COD_KING_INITIALIZED = true;
    if (isCheckoutOrOrderPage()) {
      debugLog(
        "From script_react_new.js: Came to checkout page or thank you page"
      );
    } else {
      if (document.readyState !== "loading") {
        debugLog("Document is already ready, just execute code here");
        initializeApp();
      } else {
        document.addEventListener("DOMContentLoaded", function () {
          debugLog("Document was not ready, place code here");
          initializeApp();
        });
      }
    }
  }
};

const initializeApp = () => {
  debugLog("App is initialized");
  try {
    let existingElement = document.getElementById("codking-otp-login");

    if (!existingElement) {
      debugLog("Target element not found. Creating a new one.");
      existingElement = document.createElement("div");
      existingElement.id = "codking-otp-login";
      document.body.appendChild(existingElement);
    } else {
      debugLog("Using existing HTML structure from Liquid file.");
    }

    if (existingElement instanceof HTMLElement) {
      const otpRoot = createRoot(existingElement);
      otpRoot.render(<App />);
    } else {
      throw new Error("Target container is not a DOM element.");
    }
  } catch (error) {
    console.error("Error initializing the app:", error);
  }
};

const App = () => {
  return (
    <>
      <OTPManager />
      {/* If you need to use OTPManagerWrapper, ensure it's correctly imported and exported */}
      {/* <OTPManagerWrapper /> */}
    </>
  );
};

export default App;

// Directly call initializeApp to ensure execution
InitAppScript();
