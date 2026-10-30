import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import OTPManager from "./Modal/components/OTPManager";
import AppScript from "./Components/AppScript";
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
      debugLog("Came to checkout page or thank you page");

      const node = document.createElement("div");
      node.id = "birdchime-cod-box";
      const mainContent = document.querySelector(".main__content");
      if (mainContent) {
        mainContent.prepend(node);
      }
      const root = createRoot(node);
      root.render(<AppScript />);
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

// import React, { lazy, Suspense } from "react";
// import { createRoot } from "react-dom/client";
// // Remove this direct import:
// // import OTPManager from "./Modal/components/OTPManager";

// import AppScript from "./Components/AppScript";
// // Keep OTPManagerWrapper import if you need it
// // import OTPManagerWrapper from "./Modal/components/OTPManagerWrapper";
// import { debugLog } from "./Modal/utilities/otpUtils";

// // ✅ ADD: Lazy load the heavy component
// const OTPManager = lazy(() => import("./Modal/components/OTPManager"));

// // ✅ ADD: Simple loading fallback
// const LoadingFallback = () => (
//   <div
//     style={{
//       display: "flex",
//       justifyContent: "center",
//       alignItems: "center",
//       padding: "20px",
//       fontFamily: "system-ui, sans-serif",
//     }}
//   >
//     <div
//       style={{
//         width: "32px",
//         height: "32px",
//         border: "3px solid #f3f3f3",
//         borderTop: "3px solid #3b82f6",
//         borderRadius: "50%",
//         animation: "spin 1s linear infinite",
//       }}
//     ></div>
//     <span style={{ marginLeft: "12px", color: "#6b7280" }}>Loading...</span>
//     <style>{`
//       @keyframes spin {
//         0% { transform: rotate(0deg); }
//         100% { transform: rotate(360deg); }
//       }
//     `}</style>
//   </div>
// );

// const isCheckoutOrOrderPage = () => {
//   const url = window.location.href;
//   const pathCheck = url.match(/\/checkouts\b|\/orders\b/);
//   const queryCheck =
//     url.includes("checkout_url=") || url.includes("orders_url=");
//   return pathCheck && !queryCheck;
// };

// const InitAppScript = () => {
//   if (!window.COD_KING_INITIALIZED) {
//     window.COD_KING_INITIALIZED = true;
//     if (isCheckoutOrOrderPage()) {
//       debugLog("Came to checkout page or thank you page");

//       const node = document.createElement("div");
//       node.id = "birdchime-cod-box";
//       const mainContent = document.querySelector(".main__content");
//       if (mainContent) {
//         mainContent.prepend(node);
//       }
//       const root = createRoot(node);
//       root.render(<AppScript />);
//     } else {
//       if (document.readyState !== "loading") {
//         debugLog("Document is already ready, just execute code here");
//         initializeApp();
//       } else {
//         document.addEventListener("DOMContentLoaded", function () {
//           debugLog("Document was not ready, place code here");
//           initializeApp();
//         });
//       }
//     }
//   }
// };

// const initializeApp = () => {
//   debugLog("App is initialized");
//   try {
//     let existingElement = document.getElementById("codking-otp-login");

//     if (!existingElement) {
//       debugLog("Target element not found. Creating a new one.");
//       existingElement = document.createElement("div");
//       existingElement.id = "codking-otp-login";
//       document.body.appendChild(existingElement);
//     } else {
//       debugLog("Using existing HTML structure from Liquid file.");
//     }

//     if (existingElement instanceof HTMLElement) {
//       const otpRoot = createRoot(existingElement);
//       otpRoot.render(<App />);
//     } else {
//       throw new Error("Target container is not a DOM element.");
//     }
//   } catch (error) {
//     console.error("Error initializing the app:", error);
//   }
// };

// // ✅ MODIFIED: Wrap OTPManager in Suspense
// const App = () => {
//   return (
//     <Suspense fallback={<LoadingFallback />}>
//       <OTPManager />
//       {/* If you need to use OTPManagerWrapper, ensure it's correctly imported and exported */}
//       {/* <OTPManagerWrapper /> */}
//     </Suspense>
//   );
// };

// export default App;

// // Directly call initializeApp to ensure execution
// InitAppScript();
