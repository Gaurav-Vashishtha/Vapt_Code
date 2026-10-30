import React, { useState } from "react";
import styled, { ThemeProvider, createGlobalStyle } from "styled-components";
import Skeleton from "react-loading-skeleton";
import "react-loading-skeleton/dist/skeleton.css";
import Header from "./MobileHeader";
import CouponsCard from "./MobileCouponsCard";

import useOtpStore from "../../../stores/otpStore";
import shallow from "zustand/shallow";
// import VerifyOTPForm from "./MobileVerifyOTPForm";
// import DeliveryAddress from "./MobileDeliveryAddressComponent";
// import AddOrEditAddress from "./MobileAddorEditAddressComponent";
import VerifiedComponent from "../DesktopLayout/DesktopVerifiedPage";
import LoggedInSection from "./MobileLoggedInSection";
import EmailHeaderComponent from "../DesktopLayout/DesktopEmailHeaderComponent";
import EmailForm from "../DesktopLayout/DesktopEmailForm";
import CreateCartComponenet from "../DesktopLayout/desktopCreatngCartComponent";
import { getSessionValue } from "../../../utilities/otpUtils";
import VerifyOTPForm from "../DesktopLayout/DesktopVerifyOTPForm";
import VerifyHeaderComponent from "../DesktopLayout/DesktopVerifyOTPHeader";
import ContactHeaderComponent from "../DesktopLayout/DesktopContactHeaderComponent";

import AddOrEditAddress from "./MobileAddorEditAddressComponent";
import DeliveryAddressCODK from "./MobileDeliveryAddressComponent.js";
import DesktopFooter from "../DesktopLayout/DesktopFooter";
import MobileHeaderTop from "./MobileHeader";
import MobileSummarySection from "./MobileSummarySection.js";
import ContactForm from "./MobileContactFrom.js";
import VerifyOTPFormCODK from "./MobileVerifyOTPForm.js";
import MobilePartialPaymentComponent from "./MobilePartialPaymentComponent.js";

// Default theme
const defaultTheme = {
  primary: "#dc2626",
  primaryDark: "#b91c1c",
  secondary: "#1c1917",
  background: "#ffffff",
  cardBg: "#fff1f2",
  text: "#333333",
  border: "#e5e7eb",
};

// Global styles (if needed)
const GlobalStyle = createGlobalStyle`
  body {
    margin: 0 !important;
    font-family: 'Tasa', sans-serif !important;
    // font-size: 13px !important;
    -webkit-font-smoothing: antialiased !important;
    -moz-osx-font-smoothing: grayscale !important;
  }
  .codk-checkout-modal {
    // font-size: 13px !important;
    font-family: 'Tasa', sans-serif !important;
    // line-height: 1.6 !important;
    color: ${(props) => props.theme.text} !important;
  }
`;

// ----- Styled Components for Layout -----
const OverlayCODK = styled.div`
  position: ${(props) =>
    props.preIsLoginEnabled ? "static" : "fixed"} !important;
  top: 0 !important;
  left: 0 !important;
  right: 0 !important;
  bottom: 0 !important;
  background-color: #fff !important;
  display: flex !important;
  flex-direction: column !important;
  z-index: 1000 !important;
  height: 100vh !important;
  height: 100dvh !important; /* Dynamic viewport height for mobile browsers */
  max-height: 100vh !important; /* Fallback for browsers that don't support dvh */
  max-height: 100dvh !important; /* Dynamic viewport height */
  overflow: hidden !important;

  @media (min-width: 768px) {
    background-color: rgba(0, 0, 0, 0.5) !important;
    padding: 16px !important;
    overflow-y: auto !important;
    height: auto !important;
    max-height: none !important;
  }

  /* Handle very small mobile screens */
  @media (max-height: 600px) {
    height: 100vh !important;
    height: 100dvh !important;
  }
`;

const ContainerCODK = styled.div`
  width: 100% !important;
  height: 100% !important;
  display: flex !important;
  flex-direction: column !important;
  background-color: #fff !important;
  position: relative !important;

  @media (min-width: 768px) {
    max-width: 800px !important;
    margin: auto !important;
    border-radius: 12px !important;
    flex-direction: row !important;
    height: auto !important;
  }
`;

// Sticky Header Container
const StickyHeaderContainer = styled.div`
  position: fixed !important;
  top: 0 !important;
  left: 0 !important;
  right: 0 !important;
  z-index: 1001 !important;
  background-color: #fff !important;

  @media (min-width: 768px) {
    position: relative !important;
    z-index: auto !important;
  }
`;

// Sticky Summary Section
const StickySummaryContainer = styled.div`
  position: fixed !important;
  top: 60px !important; /* Adjust based on header height */
  left: 0 !important;
  right: 0 !important;
  z-index: 1000 !important;
  background-color: #fff !important;

  @media (min-width: 768px) {
    position: relative !important;
    top: auto !important;
    z-index: auto !important;
  }
`;

// Content wrapper with padding for sticky header and footer
// const ContentWrapperCODK = styled.div`
//   flex: 1 !important;
//   display: flex !important;
//   flex-direction: column !important;
//   height: 100vh !important;
//   overflow-y: auto !important;

//   @media (min-width: 768px) {
//     height: auto !important;
//     overflow: visible !important;
//   }
// `;

const ContentWrapperCODK = styled.div`
  flex: 1 !important;
  display: flex !important;
  flex-direction: column !important;
  height: 100vh !important;
  height: 100dvh !important; /* Dynamic viewport height for mobile browsers */
  max-height: 100vh !important; /* Fallback */
  max-height: 100dvh !important; /* Dynamic viewport height */
  overflow-y: auto !important;
  -webkit-overflow-scrolling: touch !important; /* Smooth scrolling on iOS */
  min-height: 0 !important; /* Important for flex children */

  @media (min-width: 768px) {
    height: auto !important;
    max-height: none !important;
    overflow-y: visible !important;
  }

  /* Handle very small mobile screens */
  @media (max-height: 600px) {
    height: 100vh !important;
    height: 100dvh !important;
  }
`;

const ContentSectionCODK = styled.div`
  flex: 1 !important;
  background-image: url("https://cdn.shopify.com/s/files/1/0743/3119/3628/files/rings.svg?v=1750424363"),
    url("https://cdn.shopify.com/s/files/1/0743/3119/3628/files/shiny-overlay_0cc9fc85-7914-4ccb-af64-cb9ed360c2da.svg?v=1750019974"),
    linear-gradient(
      to bottom right,
      ${(props) => props.theme.secondary},
      ${(props) => props.theme.cardBg}
    ) !important;
  background-repeat: no-repeat, no-repeat, no-repeat !important;
  background-position: top left, bottom right, center !important;
  background-size: 300px, 500px, cover !important;
  overflow-y: auto !important;
  height: 100% !important;
  min-height: 0 !important; /* Important for flex children */
  -webkit-overflow-scrolling: touch !important; /* Smooth scrolling on iOS */

  @media (min-width: 768px) {
    height: calc(100vh - 100px) !important;
  }

  /* Handle very small mobile screens */
  @media (max-height: 600px) {
    overflow-y: auto !important;
  }
`;

const InnerContent = styled.div`
  padding: 20px !important;
`;

const CenteredDivCODK = styled.div`
  display: flex !important;
  justify-content: center !important;
  align-items: center !important;
  margin-bottom: 12px !important;
`;

const SummaryWrapper = styled.div`
  margin: 0 !important;
  padding: 0 !important;
  background-color: transparent !important;
`;

// const ContactScrollContainer = styled.div`
//   height: calc(100vh - 120px); // Adjust based on sticky header + footer height
//   overflow-y: auto;
//   -webkit-overflow-scrolling: touch;
//   padding-bottom: 16px;

//   @media (min-width: 768px) {
//     height: auto;
//     overflow: visible;
//   }
// `;

const ContactScrollContainer = styled.div`
  flex: 1;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  padding-bottom: 16px;
  min-height: 0; /* Important for flex children */

  @media (min-width: 768px) {
    height: auto;
    overflow: visible;
  }
`;

export default function MobileLayout({ onClose, theme = {} }) {
  const [formData, setFormData] = useState({
    phone: "",
    email: "",
    receiveUpdates: true,
  });

  const currentTheme = { ...defaultTheme, ...theme };

  const {
    otpData,
    isPartialCartRevertToOriginalCartCompleted,
    isCartReady,
    orderSummary,
    currentCartData,
  } = useOtpStore(
    (state) => ({
      otpData: state.otpData,
      isPartialCartRevertToOriginalCartCompleted:
        state.isPartialCartRevertToOriginalCartCompleted,
      isCartReady: state.isCartReady,
      orderSummary: state.orderSummary,
      currentCartData: state.currentCartData,
    }),
    shallow
  );
  const settings = getSessionValue("settingSession");

  const { step } = otpData;
  const { preIsLoginEnabled, preV2ShowOrderSummary, enablePreOrderOtp } =
    settings;

  return (
    <ThemeProvider theme={currentTheme}>
      <OverlayCODK
        className="codk-checkout-modal"
        preIsLoginEnabled={settings?.preIsLoginEnabled}
      >
        <GlobalStyle theme={currentTheme} />
        <ContainerCODK>
          {/* Sticky Header Section */}
          <StickyHeaderContainer>
            <MobileHeaderTop theme={currentTheme} onClose={onClose} />
          </StickyHeaderContainer>

          {/* Content Wrapper with proper spacing */}
          <ContentWrapperCODK>
            {/* Content Section */}
            <ContentSectionCODK>
              {!isCartReady && console.log("isCartReady", isCartReady) ? (
                <div style={{ padding: "20px" }}>
                  <Skeleton height={40} style={{ marginBottom: "12px" }} />
                  <Skeleton height={100} style={{ marginBottom: "12px" }} />
                  <Skeleton height={40} width="70%" />
                </div>
              ) : (
                <>
                  <SummaryWrapper
                    style={{
                      display: step === 1 || step === 2 ? "block" : "none",
                    }}
                  >
                    <MobileSummarySection
                      theme={currentTheme}
                      onClose={onClose}
                    />
                  </SummaryWrapper>
                  {/* Coupons Card */}
                  {/* <CouponsCard theme={currentTheme} /> */}

                  <InnerContent>
                    {step === 1 && (
                      <ContactScrollContainer>
                        <ContactHeaderComponent theme={currentTheme} />
                        <ContactForm
                          theme={currentTheme}
                          formData={formData}
                          setFormData={setFormData}
                        />
                      </ContactScrollContainer>
                    )}
                    {step === 2 && (
                      <>
                        <CenteredDivCODK>
                          <VerifyHeaderComponent theme={currentTheme} />
                        </CenteredDivCODK>

                        <VerifyOTPFormCODK theme={currentTheme} />
                      </>
                    )}
                    {step === 3 && (
                      <>
                        <DeliveryAddressCODK theme={currentTheme} />
                      </>
                    )}
                    {step === 4 && (
                      <>
                        <AddOrEditAddress theme={currentTheme} />
                      </>
                    )}
                    {step === 5 && <VerifiedComponent theme={currentTheme} />}
                    {step === 6 && (
                      <>
                        <EmailForm theme={currentTheme} />
                      </>
                    )}
                    {step === 7 && (
                      <>
                        <MobilePartialPaymentComponent theme={currentTheme} />
                      </>
                    )}
                  </InnerContent>
                </>
              )}
            </ContentSectionCODK>
          </ContentWrapperCODK>
        </ContainerCODK>
      </OverlayCODK>
    </ThemeProvider>
  );
}
