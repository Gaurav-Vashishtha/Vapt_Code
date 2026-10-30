import React, { useEffect } from "react";
import OtpForm from "./OtpForm.js";
import ModalLayout from "./Layout/ModalLayout.js";
import useOtpStore from "../stores/otpStore";
import { useAppContext } from "../context/AppContext";
import { trackFormView } from "../services/funnelTracker";

const OTPWidget = ({ onClose }) => {
  const {
    otpData,
    // newDesign,
    setOtpData,
    initializeOtpData,
    handlePhoneSubmit,
    settings,
    resetCurrentCartData,
    resetOrderSummary,
  } = useOtpStore();
  const { isNewDesignEnabled } = settings;
  const { step, timer } = otpData;

  // Initialize OTP data on component mount
  useEffect(() => {
    // Reset currentCartData and orderSummary to null on every popup open to ensure fresh data is fetched
    trackFormView();
    resetCurrentCartData();
    resetOrderSummary();
    initializeOtpData();
  }, []);

  // Timer management for OTP expiration
  useEffect(() => {
    let interval;
    if (timer > 0 && step === 2) {
      interval = setInterval(() => {
        setOtpData({ timer: timer - 1 });
      }, 1000);
    }
    return () => clearInterval(interval);
  }, [timer, step]);

  return (
    <>
      {isNewDesignEnabled ? (
        <ModalLayout onClose={onClose} />
      ) : (
        <OtpForm
          // handlePhoneSubmit={handlePhoneSubmitWithValidation}
          onClose={onClose}
        />
      )}
    </>
  );
};

export default OTPWidget;
