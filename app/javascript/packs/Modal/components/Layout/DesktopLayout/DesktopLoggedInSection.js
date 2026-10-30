// LoggedInSection.js
import React from "react";
import styled from "styled-components";

import { User } from "lucide-react";

import { getSessionValue } from "../../../utilities/otpUtils";
import useOtpStore from "../../../stores/otpStore";

const LoggedInSection = ({ theme }) => {
  const {
    otpData,
    setStep,
    setIsLoading,
    setIsSmsLoading,
    setisWhatsAppLoading,
  } = useOtpStore();
  const verifiedNumberData = getSessionValue("verifiedNumberData");
  const verifiedPhoneNumber =
    verifiedNumberData?.otpVerifiedPhoneNumber || otpData?.phoneNumber;

  const handleStepReset = () => {
    setIsSmsLoading(false);
    setisWhatsAppLoading(false);
    setIsLoading(false);
    setStep(1);
  };

  return (
    <StyledLoggedInSectionCODK>
      <StyledHeaderCODK>
        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
          <LoggedInIconCODK>
            <User size={16} />
          </LoggedInIconCODK>
          <span>Logged in as</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
          <span>+{verifiedPhoneNumber}</span>
          <span style={{ cursor: "pointer" }} onClick={handleStepReset}>
            ›
          </span>
        </div>
      </StyledHeaderCODK>
    </StyledLoggedInSectionCODK>
  );
};

export default LoggedInSection;

/* ====== STYLES ====== */

const StyledLoggedInSectionCODK = styled.div`
  /* Matches the "Order summary" card look */
  background: #f4f4f6 !important;
  border-radius: 12px !important;
  padding: 12px !important;
  box-shadow: 0px 2px 6px rgba(0, 0, 0, 0.05) !important;
  position: relative !important;
  margin-top: 25px !important;
`;

const StyledHeaderCODK = styled.div`
  /* Replacing 'StyledCouponsHeader' with a matching style from snippet */
  display: flex !important;
  justify-content: space-between !important;
  align-items: center !important;
  font-size: 11px !important; /* Slightly bigger text like snippet */
  font-weight: 600 !important;
  color: #333 !important; /* Dark gray text from snippet */
  padding-bottom: 6px !important; /* Minor spacing like snippet */
`;

const LoggedInIconCODK = styled.div`
  width: 24px !important;
  height: 24px !important;
  background-color: #fff !important;
  border-radius: 50% !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  color: ${(props) => props.theme.primary} !important;
  /* Add a subtle shadow & border for a layered look */
  box-shadow: 0px 2px 4px rgba(0, 0, 0, 0.1) !important;
  border: 2px solid #fff !important;
`;
