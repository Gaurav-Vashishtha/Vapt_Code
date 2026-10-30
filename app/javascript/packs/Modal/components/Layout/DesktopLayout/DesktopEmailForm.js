import React, { useState, useEffect } from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import StickyFooterWithSummary from "../MobileLayout/MobileStickyFooterWithSummary";
import CodkingButton from "../CommonComponent/codKingButton";
import EmailHeaderComponent from "./DesktopEmailHeaderComponent";

const EmailForm = ({ theme, formData, setFormData }) => {
  const { handleEmailSubmit, otpData, setOtpData, isCartReady } = useOtpStore();
  const { error, isLoading } = otpData;
  const [email, setEmail] = useState("");
  const [emailError, setEmailError] = useState("");

  useEffect(() => {
    setOtpData({ currentProgressBarStep: 0 }); // Contact selected
  }, []);

  const validateEmail = (email) => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  };

  const handleEmailChange = (e) => {
    const newEmail = e.target.value;
    setEmail(newEmail);

    if (newEmail && !validateEmail(newEmail)) {
      setEmailError("Please enter a valid email address");
    } else {
      setEmailError("");
    }
  };

  const handleSubmit = () => {
    if (!email) {
      setEmailError("Email is required");
      return;
    }

    if (!validateEmail(email)) {
      setEmailError("Please enter a valid email address");
      return;
    }

    handleEmailSubmit(email);
  };

  return (
    <>
      {/* Form */}
      <EmailHeaderComponent theme={theme} />
      <FormCODK onSubmit={(e) => e.preventDefault()}>
        <InputCODK
          type="email"
          value={email}
          onChange={handleEmailChange}
          placeholder="Enter your email"
          style={{ borderColor: emailError ? "red" : undefined }}
        />
        {emailError && (
          <div style={{ color: "red", fontSize: "12px", marginTop: "5px" }}>
            {emailError}
          </div>
        )}
        {error && <ErrorCODK>{error}</ErrorCODK>}

        {window.innerWidth <= 768 ? (
          <StickyFooterWithSummary>
            <CodkingButton
              onClick={handleSubmit}
              disabled={!isCartReady}
              loading={isLoading}
            >
              Continue
            </CodkingButton>
          </StickyFooterWithSummary>
        ) : (
          <CodkingButton
            onClick={handleSubmit}
            disabled={!isCartReady}
            loading={isLoading}
          >
            Continue
          </CodkingButton>
        )}
      </FormCODK>
    </>
  );
};

export default EmailForm;
const InputCODK = styled.input`
  width: 100% !important;
  height: 43px !important;
  font-size: 15px !important;
  line-height: 17px !important;
  border-radius: 8px !important;
  border: 1px solid #d1d5db !important;
  font-weight: 500 !important;
  transition: border-color 0.3s ease-in-out, box-shadow 0.3s ease-in-out !important;
  background-color: white !important;
  color: #333 !important;
  outline: none !important;
  padding: 12px !important;

  &:focus {
    border-color: black !important;
    box-shadow: 0px 4px 8px rgba(0, 0, 0, 0.1) !important;
  }
`;

const ErrorCODK = styled.div`
  color: red !important;
  font-size: 12px !important;
`;

// Styled Components
const FormCODK = styled.form`
  display: flex !important;
  flex-direction: column !important;
  gap: 16px !important;
`;

const ButtonCODK = styled.button`
  width: auto !important; /* Adjusts based on content */
  min-width: 160px !important; /* Ensures minimum width */
  padding: 12px 24px !important; /* Balanced padding */
  background-color: ${(props) =>
    props.bgColor || props.theme.primary} !important; /* Dynamic Background */
  color: ${(props) =>
    props.textColor ||
    props.theme.secondary} !important; /* Dynamic Text Color */
  border: none !important;
  border-radius: 30px !important; /* Rounded corners */
  font-size: 12.5px !important;
  font-weight: 600 !important;
  cursor: pointer !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 8px !important;
  transition: background-color 0.3s ease-in-out, box-shadow 0.3s,
    transform 0.2s ease-in-out !important;
  box-shadow: 0px 4px 6px rgba(0, 0, 0, 0.1) !important; /* Soft shadow */

  &:hover {
    background-color: ${(props) =>
      props.hoverBgColor ||
      props.theme.primaryDark} !important; /* Dynamic Hover Color */
    box-shadow: 0px 6px 12px rgba(0, 0, 0, 0.2) !important;
  }

  &:active {
    transform: scale(0.97) !important; /* Subtle press effect */
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
