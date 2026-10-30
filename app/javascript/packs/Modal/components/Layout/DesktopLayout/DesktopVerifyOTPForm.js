import React, { useEffect } from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import OTPInput from "react-otp-input";
import CodkingButton from "../CommonComponent/codKingButton";
import StickyFooter from "../MobileLayout/MobileFooterSection";

const VerifyOTPFormCODK = ({ theme }) => {
  const {
    otpData,
    setOtp,
    handleOtpSubmit,
    handleResendOtp,
    settings,
    shippingAddressCount,
    isCartReady,
  } = useOtpStore();
  const { otp, timer, isLoading, error, showResendLink, showServerErrorText } =
    otpData;

  useEffect(() => {
    const style = document.createElement("style");
    style.innerHTML = `
      input[type="number"]::-webkit-inner-spin-button,
      input[type="number"] {
        -webkit-appearance: none;
        -moz-appearance: textfield;
        appearance: none;
        margin: 0;
      }
    `;
    document.head.appendChild(style);
    return () => document.head.removeChild(style);
  }, []);

  const handleOtpChange = (newOtp) => {
    setOtp(newOtp);
    if (newOtp.length === 4 && !isLoading) {
      handleOtpSubmit("SMS");
    }
  };

  return (
    <OTPFormContainerCODK theme={theme}>
      <FormCODK onSubmit={(e) => e.preventDefault()}>
        <OTPWrapperCODK>
          <OTPInput
            value={otp}
            onChange={handleOtpChange}
            numInputs={4}
            inputType="number"
            shouldAutoFocus
            renderSeparator={<span>&nbsp;</span>}
            renderInput={(props) => <OTPBoxCODK {...props} />}
          />
        </OTPWrapperCODK>
        <ErrorTextCODK>
          {error && <p>{error}</p>}
          {showServerErrorText && <p>{settings.SERVER_ERROR_TEXT}</p>}
        </ErrorTextCODK>
        <ResendContainerCODK>
          <span>
            {settings.DID_NOT_RECEIVE_OTP_TEXT || "Didn't receive the OTP?"}
            <div>
              Retry in <b>00:{timer < 10 ? `0${timer}` : timer}</b>
            </div>
          </span>
          {showResendLink && (
            <ResendLinkCODK
              onClick={() => {
                if (timer === 0) {
                  handleResendOtp();
                }
              }}
              disabled={timer !== 0}
            >
              {settings.RESEND_LINK_TEXT || "Resend"}
            </ResendLinkCODK>
          )}
        </ResendContainerCODK>

        {shippingAddressCount > 0 && (
          <ShippingCountText>
            <b>{shippingAddressCount}</b>{" "}
            {shippingAddressCount === 1 ? "Address found" : "Addresses found"}
          </ShippingCountText>
        )}

        <CodkingButton
          onClick={() => handleOtpSubmit("SMS")}
          disabled={!isCartReady}
          loading={isLoading}
        >
          {settings.verifyBtnText || "Continue"}
        </CodkingButton>

        {/* <ButtonCODK onClick={() => handleOtpSubmit("SMS")} disabled={isLoading}>
          {isLoading ? "Verifying..." : settings.verifyBtnText || "Continue"}
        </ButtonCODK> */}
      </FormCODK>
    </OTPFormContainerCODK>
  );
};

export default VerifyOTPFormCODK;

// Styled Components

const OTPFormContainerCODK = styled.div`
  padding-bottom: 60px !important;
  display: flex !important;
  flex-direction: column !important;
  align-items: center !important;
`;

const FormCODK = styled.form`
  display: flex !important;
  flex-direction: column !important;
  gap: 14px !important;
  width: 100% !important;
  max-width: 320px !important;
`;

const OTPWrapperCODK = styled.div`
  display: flex !important;
  justify-content: center !important;
  gap: 10px !important;
  margin-bottom: 10px !important;
`;

const OTPBoxCODK = styled.input`
  width: 60px !important;
  height: 60px !important;
  border: 1.5px solid #ced4da !important;
  border-radius: 8px !important;
  font-size: 20px !important;
  text-align: center !important;
  color: #495057 !important;
  background: #fff !important;
  margin: 2px !important;
  transition: border-color 0.3s ease, box-shadow 0.3s ease !important;

  &:focus {
    border-color: ${(props) => props.theme.primary} !important;
    outline: none !important;
    box-shadow: 0px 0px 8px rgba(220, 38, 38, 0.3) !important;
  }

  &:hover {
    border-color: ${(props) => props.theme.primaryDark} !important;
  }
`;

const ErrorTextCODK = styled.div`
  color: red !important;
  font-size: 13px !important;
  text-align: center !important;
`;

const ResendContainerCODK = styled.div`
  display: flex !important;
  justify-content: space-between !important;
  margin: 4px 0 0 !important;
  color: #666 !important;
  font-size: 14px !important;
`;

const ResendLinkCODK = styled.span`
  font-size: 14px !important;
  cursor: pointer !important;
  color: #2563eb !important;
  font-weight: 500 !important;

  &:hover {
    color: #1d4ed8 !important;
  }
`;

const ButtonCODK = styled.button`
  width: auto !important;
  min-width: 160px !important;
  padding: 12px 24px !important;
  background-color: ${(props) =>
    props.bgColor || props.theme.primary} !important;
  color: ${(props) => props.textColor || props.theme.secondary} !important;
  border: none !important;
  border-radius: 30px !important;
  font-size: 12.5px !important;
  font-weight: 600 !important;
  cursor: pointer !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 8px !important;
  transition: background-color 0.3s ease-in-out, box-shadow 0.3s,
    transform 0.2s ease-in-out !important;
  box-shadow: 0px 4px 6px rgba(0, 0, 0, 0.1) !important;

  &:hover {
    background-color: ${(props) =>
      props.hoverBgColor || props.theme.primaryDark} !important;
    box-shadow: 0px 6px 12px rgba(0, 0, 0, 0.2) !important;
  }

  &:active {
    transform: scale(0.97) !important;
    box-shadow: inset 0px 3px 6px rgba(0, 0, 0, 0.2) !important;
  }

  &:disabled {
    background-color: ${(props) =>
      props.disabledBgColor || props.theme.border} !important;
    color: ${(props) => props.disabledTextColor || props.theme.text} !important;
    cursor: not-allowed !important;
    box-shadow: none !important;
  }
`;

const ShippingCountText = styled.div`
  font-size: 13px !important;
  color: #374151 !important;
  text-align: center !important;
  margin-top: 10px !important;
`;
