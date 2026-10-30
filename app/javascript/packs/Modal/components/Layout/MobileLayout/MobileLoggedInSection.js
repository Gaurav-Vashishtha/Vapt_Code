import React from "react";
import { User } from "lucide-react";

import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import { getSessionValue } from "../../../utilities/otpUtils";

const LoggedInSection = ({ theme }) => {
  const { otpData, setStep } = useOtpStore();
  const verifiedNumberData = getSessionValue("verifiedNumberData");
  const verifiedPhoneNumber =
    verifiedNumberData?.otpVerifiedPhoneNumber || otpData?.phoneNumber;

  return (
    <StyledLoggedInCODK theme={theme}>
      <LoggedInHeaderCODK>
        <LoggedInLeftCODK>
          <CouponIconCODK>
            <User size={16} />
          </CouponIconCODK>
          <LoggedInTitleCODK>Logged in as</LoggedInTitleCODK>
        </LoggedInLeftCODK>
        <LoggedInRightCODK>
          <LoggedInCountCODK>
            <span>+{verifiedPhoneNumber}</span>
          </LoggedInCountCODK>
          <span style={{ cursor: "pointer" }} onClick={() => setStep(1)}>
            <ArrowCODK>&gt;</ArrowCODK>
          </span>
        </LoggedInRightCODK>
      </LoggedInHeaderCODK>
    </StyledLoggedInCODK>
  );
};

export default LoggedInSection;

// Styled LoggedIn Card
const StyledLoggedInCODK = styled.div`
  background-color: ${(props) => props.theme.cardBg} !important;
  border-radius: 12px !important;
  padding: 16px !important;
  margin-bottom: 24px !important;
`;

const LoggedInHeaderCODK = styled.div`
  display: flex !important;
  align-items: center !important;
  justify-content: space-between !important;
`;

const LoggedInLeftCODK = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 12px !important;
`;

const CouponIconCODK = styled.div`
  width: 32px !important;
  height: 32px !important;
  background-color: #22c55e !important;
  border-radius: 50% !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  color: #fff !important;
  font-size: 12.5px !important;
`;

const LoggedInTitleCODK = styled.span`
  font-size: 12.5px !important;
`;

const LoggedInRightCODK = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 8px !important;
`;

const LoggedInCountCODK = styled.span`
  color: #666 !important;
`;

const ArrowCODK = styled.span`
  color: #666 !important;
`;
