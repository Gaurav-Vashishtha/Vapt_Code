import React, { useState } from "react";
import styled, { createGlobalStyle, ThemeProvider } from "styled-components";
import Skeleton from "react-loading-skeleton";
import "react-loading-skeleton/dist/skeleton.css";
import CompanyHeader from "./DesktopHeader";
import OrderSummary from "./DesktopOrderSummary";
import CouponsSection from "./DesktopCouponSection";
import ProgressStepsComponent from "./DesktopProgressStepsComponent";
import ContactHeaderComponent from "./DesktopContactHeaderComponent";
import ContactForm from "./DesktopContactForm";
import PaymentLogosComponent from "./DesktopPaymentLogos";
import useOtpStore from "../../../stores/otpStore";
import VerifyOTPForm from "./DesktopVerifyOTPForm";
import VerifyHeaderComponent from "./DesktopVerifyOTPHeader";
import DeliveryAddressComponent from "./desktopDeliveryAddressComponent";
import AddOrEditAddress from "./DesktopAddorEditAddressComponent";
import LoggedInSection from "./DesktopLoggedInSection";
import VerifiedComponent from "./DesktopVerifiedPage";
import BackButton from "./DesktopBackButton";
import EmailForm from "./DesktopEmailForm";
import EmailHeaderComponent from "./DesktopEmailHeaderComponent";
import CreateCartComponenet from "./desktopCreatngCartComponent";
import { debugLog, getSessionValue } from "../../../utilities/otpUtils";
import "@fontsource/inter"; // Defaults to weight 400
import "@fontsource/inter/400.css";
import DesktopFooter from "./DesktopFooter";
import MobilePartialPaymentComponent from "../MobileLayout/MobilePartialPaymentComponent";
import { DESKTOP_PARTIAL_SCREEN_EXCEPTION_STORES } from "../../../utilities/selectors";

// Default theme (feel free to adjust colors)
const defaultTheme = {
  primary: "#dc2626",
  primaryDark: "#b91c1c",
  secondary: "#1c1917",
  background: "#ffffff",
  cardBg: "rgba(255,255,255,0.7)",
  text: "#333333",
  border: "rgba(0, 0, 0, 0.1)",
};

const GlobalStyleCODK = createGlobalStyle`
  body {
    margin: 0 !important;
    font-family: 'Inter', sans-serif !important;
    font-size: 13px !important;
    -webkit-font-smoothing: antialiased !important;
    -moz-osx-font-smoothing: grayscale !important;
  }
  .codk-checkout-modal {
    font-size: 13px !important;
    line-height: 1.6 !important;
    color: ${(props) => props.theme.text} !important;
  }
`;

// Glassmorphic modal container
const ModalContainerCODK = styled.div`
  background: ${(props) => props.theme.cardBg} !important;
  border-radius: 20px !important;
  box-shadow: 0 8px 32px rgba(31, 38, 135, 0.37) !important;
  backdrop-filter: blur(10px) !important;
  -webkit-backdrop-filter: blur(10px) !important;
  border: 1px solid rgba(255, 255, 255, 0.18) !important;
  width: ${(props) => (props.fullWidth ? "50%" : "100%")} !important;
  min-height: 500px !important;
  max-width: ${(props) => (props.fullWidth ? "600px" : "1000px")} !important;
  display: flex !important;
  overflow: hidden !important;
`;

const LeftColumnCODK = styled.div`
  position: relative !important; /* Ensures background image aligns properly */
  width: 30% !important;
  padding: 17px !important;
  color: #fff !important;
  display: flex !important;
  flex-direction: column !important;
  justify-content: space-between !important;
  border-top-left-radius: 20px !important;
  border-bottom-left-radius: 20px !important;
  // overflow-y: auto !important;
  // overflow-x: hidden !important;
  // min-height: 0 !important;

  /* Primary Gradient Background */
  // background: linear-gradient(
  //   135deg,
  //   ${(props) => props.theme.primary || "#4F2E8C"},
  //   /* Dark Purple */ ${(props) => props.theme.primaryDark || "#3E1E6A"}
  //     /* Deeper Shade */
  // );

  background: ${(props) =>
    props.theme.primary || "#4F2E8C"}; /* fallback for old browsers */
  background: -webkit-linear-gradient(
    to right,
    ${(props) => props.theme.primary || "#4F2E8C"},
    ${(props) => props.theme.primaryDark || "#3E1E6A"}
  ); /* Chrome 10-25, Safari 5.1-6 */
  background: linear-gradient(
    to right,
    ${(props) => props.theme.primary || "#4F2E8C"},
    ${(props) => props.theme.primaryDark || "#3E1E6A"}
  ); /* W3C, IE 10+/ Edge, Firefox 16+, Chrome 26+, Opera 12+, Safari 7+ */

  /* Background Image Overlay */
  &::after {
    content: "" !important;
    position: absolute !important;
    bottom: 0 !important;
    left: 0 !important;
    width: 100% !important;
    height: 50% !important; /* Ensures image remains in lower half */
    opacity: 1 !important; /* Keeps it visible */
  }
`;

const LeftColumnContent = styled.div`
  opacity: ${(props) => (props.show ? "1" : "0")} !important;
  transition: opacity 0.2s ease-in-out !important;
  margin-top: 10px !important;
`;

const LeftColumnHeader = styled.div`
  margin-bottom: 10px !important;
`;

// Header wrapper with bottom border for separation

const HeaderWrapper = styled.div`
  display: flex !important;
  justify-content: space-between !important;
  align-items: center !important;
  margin-bottom: 5px !important;
  // padding-bottom: 5px;
  border-bottom: 1px solid ${(props) => props.theme.border} !important;
`;

// Animated close button
const StyledCloseButtonCODK = styled.button`
  background: none !important;
  border: none !important;
  font-size: 28px !important;
  color: ${(props) => props.theme.text} !important;
  cursor: pointer !important;
  transition: transform 0.2s ease, color 0.2s ease !important;

  &:hover {
    transform: scale(1.1) !important;
    color: ${(props) => props.theme.primary} !important;
  }
`;

// Placeholder for any illustration or logo
const IllustrationPlaceholderCODK = styled.div`
  height: 80px !important;
  margin-bottom: 10px !important;
`;

const ModalOverlayCODK = styled.div`
  position: ${(props) =>
    props.preIsLoginEnabled ? "static" : "fixed"} !important;
  top: 0 !important;
  left: 0 !important;
  right: 0 !important;
  bottom: 0 !important;
  background: ${(props) =>
    props.preIsLoginEnabled ? "transparent" : "rgba(0, 0, 0, 0.4)"} !important;

  backdrop-filter: blur(8px) !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  padding: 20px !important;
  transition: background 0.3s ease !important;
  z-index: 1000 !important;
`;

const RightColumnCODK = styled.div`
  flex: 1 !important;
  padding: 24px !important;
  display: flex !important;
  flex-direction: column !important;
  border-top-right-radius: 20px !important;
  border-bottom-right-radius: 20px !important;
  position: relative !important;
  z-index: 1;
  // overflow-y: auto !important;
  // overflow-x: hidden !important;
  // min-height: 0 !important;

  background: url("https://cdn.shopify.com/s/files/1/0743/3119/3628/files/shiny-overlay_0cc9fc85-7914-4ccb-af64-cb9ed360c2da.svg?v=1750019974"),
    linear-gradient(
      to bottom right,
      ${(props) => props.theme.secondary},
      ${(props) => props.theme.cardBg}
    ) !important;

  background-size: cover !important;
  background-position: center !important;
  background-repeat: no-repeat !important;

  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);

  border: 1px solid rgba(0, 0, 0, 0.04);
  box-shadow: 0 6px 24px rgba(0, 0, 0, 0.06);

  transition: background 0.4s ease, box-shadow 0.3s ease !important;
`;

const StepOneContainerCODK = styled.div`
  margin: 2% 20% !important;
  // background-color: #ffffff; /* ✅ Ensuring perfect contrast */
  border-radius: 12px !important;
  padding: 20px !important;
  // box-shadow: 0 2px 10px rgba(0, 0, 0, 0.05); /* ✅ Soft shadow */
`;

const IllustrationImage = styled.img`
  position: absolute !important;
  bottom: 0 !important;
  left: 0 !important;
  width: 100% !important;
  opacity: 1 !important; /* Fully visible */
  pointer-events: none !important;
  object-fit: cover !important;
  border-bottom-left-radius: 20px !important;
`;

const ShadowDiv = styled.div`
  pointer-events: none !important;
  position: absolute !important;
  left: -150px !important;
  top: 13rem !important;
  height: 20.5rem !important;
  width: 80rem !important;
  transform: rotate(-22.6deg) !important;
  background: hsl(var(--illustration-shadow)) !important;
  opacity: 0.2 !important;
  mix-blend-mode: multiply !important;
  display: block !important;
  z-index: 1 !important;
`;

export default function DesktopLayout({ onClose, theme = {} }) {
  const [formData, setFormData] = useState({
    phone: "",
    email: "",
    receiveUpdates: true,
  });

  const currentTheme = { ...defaultTheme, ...theme };

  const {
    otpData,
    setOtpData,
    isPartialCartRevertToOriginalCartCompleted,
    isCartReady,
    orderSummary,
  } = useOtpStore();

  const {
    step,

    currentProgressBarStep,
    codkingTrusted,
    codking,
  } = otpData;
  const settings = getSessionValue("settingSession");
  const {
    preIsLoginEnabled,
    preV2ShowOrderSummary,
    enablePreOrderOtp,
    preShowBranding,
    brandLogoUrl,
  } = settings;

  const currentStep = currentProgressBarStep;

  // const handleBack = () => {
  //   debugLog("currentStep:", currentStep, "step:", step);
  //   if (currentStep === 1 || step === 2) {
  //     debugLog("Redirecting to step 1");
  //     setOtpData({
  //       currentProgressBarStep: 1,
  //       step: 1,
  //     });
  //   } else if (currentStep > 0) {
  //     debugLog("Decrementing step and progress");
  //     setOtpData({
  //       currentProgressBarStep: currentProgressBarStep - 1,
  //       step: step - 1,
  //     });
  //   }
  // };

  function IframeContent({ theme }) {
    return (
      <div style={{ padding: 0, margin: 0 }}>
        <CreateCartComponenet theme={theme} />
        <div style={{ display: "flex", justifyContent: "center" }}>
          <DesktopFooter theme={theme} />
        </div>
      </div>
    );
  }

  return (
    <ThemeProvider theme={currentTheme}>
      <GlobalStyleCODK theme={currentTheme} />
      <ModalOverlayCODK
        preIsLoginEnabled={preIsLoginEnabled}
        className="codk-checkout-modal"
      >
        <ModalContainerCODK
          theme={currentTheme}
          // fullWidth={!preV2ShowOrderSummary}
          fullWidth={false}
        >
          <LeftColumnCODK theme={currentTheme}>
            <div>
              <LeftColumnHeader>
                <CompanyHeader theme={currentTheme} />
              </LeftColumnHeader>
              <LeftColumnContent show={preV2ShowOrderSummary}>
                <OrderSummary theme={currentTheme} />
                {step !== 1 && step !== 2 && enablePreOrderOtp && (
                  <LoggedInSection theme={currentTheme} />
                )}
              </LeftColumnContent>
            </div>
            <IllustrationPlaceholderCODK />
            <ShadowDiv />
            <IllustrationImage
              src="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/codhome.svg?v=1742551075"
              alt="shopping illustration"
            />
          </LeftColumnCODK>

          <RightColumnCODK
            theme={currentTheme}
            //  fullWidth={!preV2ShowOrderSummary}
            fullWidth={false}
          >
            <StyledCloseButtonCODK
              onClick={onClose}
              style={{ position: "absolute", right: "10px", top: "3px" }}
            >
              ×
            </StyledCloseButtonCODK>

            {!isCartReady ? (
              <div style={{ padding: "40px" }}>
                <Skeleton height={40} style={{ marginBottom: "20px" }} />
                <Skeleton height={150} style={{ marginBottom: "20px" }} />
                <Skeleton height={40} width="60%" />
              </div>
            ) : (
              <>
                {step === 1 && (
                  <>
                    <StepOneContainerCODK>
                      <ContactHeaderComponent theme={currentTheme} />
                      <ContactForm
                        theme={currentTheme}
                        formData={formData}
                        setFormData={setFormData}
                      />
                    </StepOneContainerCODK>
                    <div style={{ display: "flex", justifyContent: "center" }}>
                      <DesktopFooter theme={currentTheme} />
                    </div>
                  </>
                )}
                {step === 2 && (
                  <>
                    <StepOneContainerCODK>
                      <VerifyHeaderComponent theme={currentTheme} />
                      <VerifyOTPForm theme={currentTheme} />
                    </StepOneContainerCODK>
                    <div style={{ display: "flex", justifyContent: "center" }}>
                      <DesktopFooter theme={currentTheme} />
                    </div>
                  </>
                )}
                {step === 3 && (
                  <>
                    <StepOneContainerCODK>
                      <DeliveryAddressComponent theme={currentTheme} />
                    </StepOneContainerCODK>
                  </>
                )}
                {step === 4 && <AddOrEditAddress theme={currentTheme} />}
                {step === 5 && <VerifiedComponent theme={currentTheme} />}
                {step === 6 && (
                  <>
                    <StepOneContainerCODK>
                      {/* <EmailHeaderComponent theme={currentTheme} /> */}
                      <EmailForm theme={currentTheme} />
                    </StepOneContainerCODK>

                    <div style={{ display: "flex", justifyContent: "center" }}>
                      <DesktopFooter theme={currentTheme} />
                    </div>
                  </>
                )}
                {step === 7 && (
                  <>
                    {DESKTOP_PARTIAL_SCREEN_EXCEPTION_STORES.includes(
                      window.Shopify?.shop
                    ) ? (
                      <div style={{ isolation: "isolate" }}>
                        <MobilePartialPaymentComponent theme={currentTheme} />
                      </div>
                    ) : (
                      <>
                        <CreateCartComponenet theme={currentTheme} />
                        <div
                          style={{ display: "flex", justifyContent: "center" }}
                        >
                          <DesktopFooter theme={currentTheme} />
                        </div>
                      </>
                    )}
                  </>
                )}
              </>
            )}
          </RightColumnCODK>
        </ModalContainerCODK>
      </ModalOverlayCODK>
    </ThemeProvider>
  );
}
