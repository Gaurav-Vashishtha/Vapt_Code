import React from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import { getSessionValue } from "../../../utilities/otpUtils";
import MobileHeaderTop from "./MobileHeader";
import DesktopOrderSummary from "../DesktopLayout/DesktopOrderSummary";
import LoggedInSection from "../DesktopLayout/DesktopLoggedInSection";

const MobileSummarySection = ({ theme, onClose }) => {
  const { otpData } = useOtpStore();
  const { step } = otpData;

  const settings = getSessionValue("settingSession");
  const { preIsLoginEnabled, preV2ShowOrderSummary, enablePreOrderOtp } =
    settings;

  return (
    <>
      <StyledHeader theme={theme}>
        {/* <MobileHeaderTop theme={theme} onClose={onClose} /> */}
        <LeftColumnContent show={preV2ShowOrderSummary}>
          <DesktopOrderSummary theme={theme} />
        </LeftColumnContent>
        {step !== 1 && step !== 2 && enablePreOrderOtp && (
          <LoggedInSection theme={theme} />
        )}
      </StyledHeader>
      {/* <StickySpan /> */}
    </>
  );
};

export default MobileSummarySection;

// Styles
const StyledHeader = styled.div`
  background-color: ${(props) => props.theme.primaryDark};
  // background: -webkit-linear-gradient(
  //   to right,
  //   ${(props) => props.theme.primary || "#4F2E8C"},
  //   ${(props) => props.theme.primaryDark || "#3E1E6A"}
  // );
  // background: linear-gradient(
  //   to right,
  //   ${(props) => props.theme.primary || "#4F2E8C"},
  //   ${(props) => props.theme.primaryDark || "#3E1E6A"}
  // );

  padding: 16px;
  padding-top: 60px;
  top: 0;
  border-bottom-left-radius: 20px !important;
  border-bottom-right-radius: 20px !important;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.1);
`;

const LeftColumnContent = styled.div`
  opacity: ${(props) => (props.show ? "1" : "0")} !important;
  transition: opacity 0.2s ease-in-out !important;
`;

const StickySpan = styled.span`
  position: sticky;
  display: block;
  height: 17px;
  width: 100%;
  z-index: 1;
  border-top: 35px solid rgba(0, 0, 0, 0.1);
  background-color: #a5a0a0;
  border-bottom-left-radius: 20px;
  border-bottom-right-radius: 20px;
  margin-top: -16px;
  box-shadow: 0px 4px 16px rgba(0, 0, 0, 0.1);
  background-image: linear-gradient(
    to right,
    rgba(255, 255, 255, 0) 0%,
    rgba(255, 255, 255, 0.4) 50%,
    rgba(255, 255, 255, 0) 100%
  );
  background-repeat: no-repeat;
  background-size: 100% 100%;
`;
