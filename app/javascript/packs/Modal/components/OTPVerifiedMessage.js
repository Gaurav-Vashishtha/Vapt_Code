import React, { useEffect, useState } from "react";
import VerifiedLottiePlayer from "./assets/VerifiedLottiePlayer"; // Adjust path if necessary
import {
  debugLog,
  getSessionValue,
  OTP_VERIFIED_TEXT,
  removeSessionValue,
  setSessionValue,
} from "../utilities/otpUtils"; // Adjust path if necessary
import useOtpStore from "../stores/otpStore";
import { IS_BUY_NOW_BUTTON } from "../services/domUtils";

// Helper function to check if the product details trigger is active

// Main component that displays the OTP verified message and handles redirection
const OtpVerifiedMessage = ({ onClose }) => {
  const { redirectTOCheckout, isCartManipulationProcessCompleted } =
    useOtpStore();
  const isFetchProductDetailsTriggerActive = () =>
    getSessionValue("fetchProductDetailsTrigger") == "true";
  const [triggerActive, setTriggerActive] = useState(
    isFetchProductDetailsTriggerActive()
  );

  // Monitor the session storage trigger for fetching product details
  const monitorProductDetailsTrigger = () => {
    const currentTriggerState = isFetchProductDetailsTriggerActive();
    setTriggerActive(currentTriggerState);
  };

  // useEffect to periodically check the trigger every second
  useEffect(() => {
    const triggerInterval = setInterval(monitorProductDetailsTrigger, 200);
    return () => clearInterval(triggerInterval);
  }, []);

  // Redirect for "Buy Now" flow when the trigger is active
  const handleBuyNowFlow = () => {
    if (triggerActive) {
      redirectTOCheckout();
      setSessionValue("fetchProductDetailsTrigger", "false");
      debugLog(
        "Trigger detected for 'Buy Now' flow. Redirecting to checkout..."
      );
    }
  };

  // Consolidated useEffect to handle all redirection scenarios
  useEffect(() => {
    let isRedirecting = false; // Guard flag to prevent duplicate calls

    const handleRedirect = async () => {
      if (isRedirecting) return; // Prevent duplicate calls
      isRedirecting = true;

      if (IS_BUY_NOW_BUTTON && triggerActive == true) {
        handleBuyNowFlow();
      } else if (!IS_BUY_NOW_BUTTON) {
        redirectTOCheckout();
        debugLog(
          "Non 'Buy Now' flow detected. Redirecting to checkout immediately..."
        );
      }
    };

    handleRedirect();
  }, [triggerActive]); // Single dependency

  return (
    <div
      style={{
        background: "#fafafa",
        padding: "40px",
        borderRadius: "12px",
        boxShadow: "0 10px 40px rgba(0, 0, 0, 0.2)",
        maxWidth: "480px",
        position: "relative",
        textAlign: "center",
        margin: "auto",
        zIndex: Number.MAX_SAFE_INTEGER,
      }}
    >
      {/* Close Button */}
      <button
        onClick={onClose}
        style={{
          position: "absolute",
          top: "20px",
          right: "20px",
          background: "transparent",
          border: "none",
          fontSize: "26px",
          cursor: "pointer",
          color: "#495057",
          transition: "color 0.3s ease, transform 0.2s ease",
        }}
        aria-label="Close"
      >
        &times;
      </button>

      {/* Verification Animation and Message */}
      <div>
        <VerifiedLottiePlayer />
        <div
          style={{
            fontSize: "16px",
            color: "green",
            fontWeight: "bold",
            marginTop: "20px",
          }}
        >
          {OTP_VERIFIED_TEXT}
        </div>
      </div>
    </div>
  );
};

export default OtpVerifiedMessage;
