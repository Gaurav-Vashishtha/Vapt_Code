import React from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
// ProgressSteps Component

const ProgressStepsComponent = ({ currentStep, theme }) => {
  const { settings } = useOtpStore();

  const steps = [""];

  if (settings?.enablePreOrderOtp) {
    steps.push("Login/Signup");
  }
  if (
    settings?.partialPaymentEnabled == true &&
    settings?.enablePreOrderOtp == false
  ) {
    steps.push("Cart Creation");
  }
  // Dynamically add steps based on settings
  if (settings?.isPrefilledAddressEnabled) {
    steps.push("Address");
  }
  // if (settings.partialPayment) {
  //   steps.push("Payment");
  // }

  return (
    <StyledProgressSteps>
      {steps.map((step, index) => (
        <Step key={step} active={index === currentStep} theme={theme}>
          {/* {`${index + 1}. ${step}`} */}
          {` ${step}`}
        </Step>
      ))}
    </StyledProgressSteps>
  );
};
export default ProgressStepsComponent;
// StyledProgressSteps
const StyledProgressSteps = styled.div`
  display: flex;
  gap: 16px;
`;

const Step = styled.div`
  color: ${(props) => (props.active ? props.theme.primary : "#666")};
  font-size: 14px;
  position: relative;
  &::after {
    content: "";
    position: absolute;
    bottom: -4px;
    left: 0;
    right: 0;
    height: 2px;
    background-color: ${(props) =>
      props.active ? props.theme.primary : "transparent"};
  }
`;
