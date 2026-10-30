import React from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import {
  ENTER_CODE_SEND_TO,
  VERIFY_MOBILE_NUMBER,
} from "../../../utilities/otpUtils";

// VerifyHeader Component
const VerifyHeaderComponent = ({ theme }) => {
  const { otpData, onChangePhonNoBtnClick } = useOtpStore();
  const { phoneNumber } = otpData;

  return (
    <StyledVerifyHeaderCODK>
      
      <VerifyTitleCODK>
        {VERIFY_MOBILE_NUMBER || "Verify Mobile Number"}
      </VerifyTitleCODK>
      <VerifySubtitleCODK>
        {ENTER_CODE_SEND_TO || "Enter the code sent to"}
        <b> +{phoneNumber}</b>
        <EditButtonCODK onClick={onChangePhonNoBtnClick}>Edit</EditButtonCODK>
      </VerifySubtitleCODK>
    </StyledVerifyHeaderCODK>
  );
};

export default VerifyHeaderComponent;

// Styled Components

const StyledVerifyHeaderCODK = styled.div`
  display: flex !important;
  flex-direction: column !important;
  align-items: flex-start !important;
  gap: 6px !important;
  // margin-bottom: 5px !important;
`;

const VerifyTitleCODK = styled.div`
  font-size: 20px !important;
  line-height: 28px !important;
  font-weight: 600 !important;
  --tw-text-opacity: 1;

  @media (max-width: 768px) {
    font-size: 20px !important;
    line-height: 28px !important;
    font-weight: 599 !important;
  }
`;

const VerifySubtitleCODK = styled.p`
  margin: 4px 0 0 !important;
  color: #666 !important;
  font-size: 14px !important;
  margin-bottom: 14px !important;
`;

const EditButtonCODK = styled.button`
  background: none !important;
  border: none !important;
  font-size: 14px !important;
  font-weight: 500 !important;
  color: #2563eb !important; /* Blue color for edit link */
  margin-left: 6px !important;
  cursor: pointer !important;
  padding: 2px !important;
  transition: color 0.2s ease, text-decoration 0.2s ease !important;

  &:hover {
    color: #1d4ed8 !important; /* Darker blue on hover */
    text-decoration: underline !important;
  }

  &:focus {
    outline: none !important;
  }
`;
