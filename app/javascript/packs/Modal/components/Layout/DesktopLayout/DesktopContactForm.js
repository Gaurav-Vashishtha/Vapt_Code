import React, { useState, useEffect } from "react";
import styled from "styled-components";
import PhoneInputBox from "../../PhoneInputBox";
import useOtpStore from "../../../stores/otpStore";
import { useAppContext } from "../../../context/AppContext";
import SlidingOrderSummary from "./DesktopSlider";

import { MessageCircle, ArrowRight } from "lucide-react";

import { getSessionValue } from "../../../utilities/otpUtils";
import CodkingButton from "../CommonComponent/codKingButton";
import StickyFooter from "../MobileLayout/MobileFooterSection";
import DesktopFooter from "./DesktopFooter";

// Updated SkipButton with renamed styled component
const SkipButton = ({ onClick, disabled, isLoading, buttonText = "Skip" }) => {
  return (
    <StyledSkipButtonCODK onClick={onClick} disabled={disabled}>
      {isLoading ? "Skipping..." : buttonText}
      <ArrowRight size={18} />
    </StyledSkipButtonCODK>
  );
};

const ContactForm = ({ theme, formData, setFormData }) => {
  const {
    isSmsLoading,
    isWhatsappLoading,
    isSkipLoading,
    otpData,
    setError,
    handlePhoneSubmitSms,
    handlePhoneSubmitWhatsapp,
    handleSkip,
    // settings,
    setOtpData,
    setMode,
    isCartManipulationProcessCompleted,
    isCartReady,
  } = useOtpStore();

  const { step, otp, phoneNumber, timer, isLoading, error } = otpData;
  const settings = getSessionValue("settingSession");
  useEffect(() => {
    setOtpData({ currentProgressBarStep: 0 }); // contact selected
  }, []);

  return (
    <>
      {/* <SlidingOrderSummary /> */}
      {/* Form */}
      <FormCODK onSubmit={(e) => e.preventDefault()}>
        <PhoneInputBox handlePhoneSubmitSms={handlePhoneSubmitSms} />

        {error && <div style={{ color: "red", fontSize: "12px" }}>{error}</div>}
        {settings.preV2ShowSendCode && (
          <CodkingButton
            onClick={handlePhoneSubmitSms}
            disabled={!isCartReady}
            loading={isSmsLoading}
          >
            {settings.sendBtnText || "Get OTP"}
          </CodkingButton>
        )}

        {settings.preWhatsappButton && (
          <CodkingButton
            onClick={() => {
              if (phoneNumber.length >= 9) {
                handlePhoneSubmitWhatsapp();
              } else {
                setError("Please enter a valid phone number");
              }
            }}
            disabled={!isCartReady}
            loading={isWhatsappLoading}
            background={"#1e8a46"}
            hoverBackground={"#21984d"}
          >
            <MessageCircle size={18} />
            &nbsp;
            {settings.preWhatsappButtonText || "Get WhatsApp OTP"}
          </CodkingButton>
        )}
        {settings.showSkipBtn && (
          <SkipButton
            type="button" // Ensures it does not trigger form submission
            onClick={handleSkip}
            disabled={!isCartReady}
            buttonText={settings.skipBtnText || "Skip"}
          />
        )}
      </FormCODK>
    </>
  );
};

export default ContactForm;

// Styled Components
const FormCODK = styled.form`
  display: flex !important;
  flex-direction: column !important;
  gap: 16px !important;
`;

const StyledSkipButtonCODK = styled.button`
  background: transparent !important;
  color: ${(props) =>
    props.disabled ? "#ccc" : props.theme.primary || "#dc2626"} !important;
  border: none !important;
  padding: 10px 16px !important;
  font-size: 12.5px !important;
  font-weight: 600 !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 6px !important;
  cursor: pointer !important;
  transition: all 0.3s ease-in-out !important;
  text-decoration: none !important;

  &:hover {
    color: ${(props) => props.theme.primaryDark || "#b91c1c"} !important;
    transform: translateX(
      4px
    ) !important; /* Slight move to the right on hover */
  }

  &:active {
    transform: scale(0.97) !important;
    opacity: 0.8 !important;
  }

  &:disabled {
    color: #aaa !important;
    cursor: not-allowed !important;
  }
`;
