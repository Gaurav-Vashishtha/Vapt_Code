// AddressForm.js
import React, { useEffect } from "react";
import styled from "styled-components";

import useOtpStore from "../../../stores/otpStore";
import { OTP_VERIFIED_TEXT } from "../../../utilities/otpUtils";
import { redirectOtpStoreToCheckout } from "../../../services/redirectOtpStoreToCheckoutService";
import { IS_BUY_NOW_BUTTON } from "../../../services/domUtils";
const VerifiedContainerCODK = styled.div`
  background: transparent !important;
  text-align: center !important;
  display: flex !important;
  flex-direction: column !important;
  align-items: center !important;
  justify-content: center !important;
  width: 100% !important;
  flex: 1 !important;
  min-height: 100% !important;
  height: 100% !important;
  margin: -24px !important;
  padding: 24px !important;
  position: absolute !important;
  top: 0 !important;
  left: 0 !important;
  right: 0 !important;
  bottom: 0 !important;

  /* Mobile styles */
  @media (max-width: 767px) {
    margin: -20px !important;
    padding: 20px !important;
    min-height: calc(
      100vh - 120px
    ) !important; /* Fallback for older browsers */
    min-height: calc(
      100dvh - 120px
    ) !important; /* Dynamic viewport height for modern browsers */
    height: 100% !important;
    position: relative !important;
  }
`;

const VerificationGIF = styled.img`
  width: 250px;
  height: 250px;
  margin: 0 auto;
  display: block;
  object-fit: contain;

  /* Mobile responsive sizing */
  @media (max-width: 767px) {
    width: 200px;
    height: 200px;
  }

  /* Very small screens */
  @media (max-width: 375px) {
    width: 180px;
    height: 180px;
  }
`;

function VerifiedComponent({ theme }) {
  const {
    redirectTOCheckout,
    isCartReady,
    isCartManipulationProcessCompleted,
  } = useOtpStore();

  // useEffect(() => {
  //   if (!IS_BUY_NOW_BUTTON) {
  //     redirectTOCheckout();
  //   } else if (IS_BUY_NOW_BUTTON && isCartManipulationProcessCompleted) {
  //     redirectTOCheckout();
  //   }
  // }, []);

  // useEffect(() => {
  //   console.log(
  //     "checkout page",
  //     IS_BUY_NOW_BUTTON,
  //     isCartManipulationProcessCompleted
  //   );
  //   if (IS_BUY_NOW_BUTTON && isCartManipulationProcessCompleted) {
  //     redirectTOCheckout();
  //   }
  // }, [isCartManipulationProcessCompleted]);
  // useEffect(() => {
  //   let isRedirecting = false; // Guard flag to prevent duplicate calls

  //   const handleRedirect = async () => {
  //     if (isRedirecting) return; // Prevent duplicate calls
  //     isRedirecting = true;

  //     console.log(
  //       "checkout page",
  //       IS_BUY_NOW_BUTTON,
  //       isCartManipulationProcessCompleted
  //     );

  //     if (!IS_BUY_NOW_BUTTON) {
  //       await redirectOtpStoreToCheckout();
  //     } else if (IS_BUY_NOW_BUTTON && isCartManipulationProcessCompleted) {
  //       await redirectOtpStoreToCheckout();
  //     }
  //   };

  //   handleRedirect();
  // }, [isCartManipulationProcessCompleted]); // Single dependency

  useEffect(() => {
    const handleRedirect = async () => {
      await redirectOtpStoreToCheckout();
    };
    handleRedirect();
  }, []);

  return (
    <VerifiedContainerCODK theme={theme}>
      <VerificationGIF
        src="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/Cart.gif?v=1763464317"
        alt="Verification"
      />
      <div style={{ fontSize: "16px", color: "green", fontWeight: "bold" }}>
        {OTP_VERIFIED_TEXT}
      </div>
    </VerifiedContainerCODK>
  );
}

export default VerifiedComponent;
