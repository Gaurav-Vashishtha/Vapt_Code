import React, { useEffect, useState } from "react";
import ReactDOM from "react-dom";
import styled from "styled-components";
import { useAppContext } from "../context/AppContext";
import { sendErrorToAPI } from "../services/errorReporter";
import OTPWidget from "./OTPWidget";
import {
  debugLog,
  getSessionValue,
  checkCartPage,
  getLocalValue,
} from "../utilities/otpUtils";
import { CartRevertService } from "../services/CartRevertService";
import { syncSessionWithCart } from "../utilities/syncSessionWithCart";
import ButtonManager from "./ButtonManager";
import { syncSessionWithSettings } from "../utilities/syncSessionWithSettings";
import useOtpStore from "../stores/otpStore";
import {
  initializeCartDrawerHiding,
  initializeCartDrawerHidingLogicFive,
  initializeCartDrawerHidingLogicFour,
  initializeCartDrawerHidingLogicThree,
  initializeCartDrawerHidingLogicTwo,
} from "../utilities/cartDrawerFuntionalities";
// Apollo Client imports removed - using lightweight GraphQL client instead
// import { loadRuleVariantArrayFromSession } from "./partialPaymentFlow/partialPaymentUtilities";

// Styled Components
const PageContainer = styled.div`
  // min-height: 100vh;
  // background-color: #f6f6f7;
  // padding: 20px;
`;

const LayoutContainer = styled.div`
  max-width: 1200px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 20px;
`;

const Section = styled.div`
  // background: white;
  // border-radius: 8px;
  // padding: 20px;
  // box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  // border: 1px solid #e1e3e5;
`;

const LoadingContainer = styled.div`
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 200px;
`;

const Spinner = styled.div`
  width: 40px;
  height: 40px;
  border: 4px solid #f3f3f3;
  border-top: 4px solid #008060;
  border-radius: 50%;
  animation: spin 1s linear infinite;

  @keyframes spin {
    0% {
      transform: rotate(0deg);
    }
    100% {
      transform: rotate(360deg);
    }
  }
`;

const LoadingText = styled.p`
  margin-left: 16px;
  font-size: 16px;
  color: #637381;
  font-weight: 500;
`;

const Banner = styled.div`
  background-color: #e0f7fa;
  border: 1px solid #00acc1;
  border-radius: 8px;
  padding: 16px;
  display: flex;
  align-items: center;
  gap: 12px;
`;

const BannerIcon = styled.div`
  width: 20px;
  height: 20px;
  background-color: #00acc1;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-weight: bold;
  font-size: 12px;
`;

const BannerContent = styled.div`
  flex: 1;
`;

const BannerTitle = styled.h3`
  margin: 0 0 4px 0;
  font-size: 16px;
  font-weight: 600;
  color: #212b36;
`;

const BannerMessage = styled.p`
  margin: 0;
  font-size: 14px;
  color: #637381;
`;

const OTPManager = ({ showModal, handleCloseModal }) => {
  // When user lands on /cart, revert cart to original state if bundler_product_created (partial payment flow)
  useEffect(() => {
    if (!checkCartPage()) return;

    const settings = getSessionValue("settingSession");
    if (Number(settings?.partialPaymentFlowVersion) === 2) return;

    const bundler_product_created = getLocalValue("bundler_product_created");
    const id = setTimeout(() => {
      if (bundler_product_created) {
        CartRevertService(true);
      }
    }, 0);
    return () => clearTimeout(id);
  }, []);

  useEffect(() => {
    const settings = getSessionValue("settingSession");
    const strategy = settings?.preV2OverwritePopupCondition || 0;

    console.log(`Initializing cart hiding with strategy: ${strategy}`);

    const executeStrategy = (strategyNum) => {
      switch (strategyNum) {
        case 0:
          console.log("Cart hiding disabled");
          return true;
        case 1:
          return initializeCartDrawerHiding();
        case 2:
          return initializeCartDrawerHidingLogicTwo();
        case 3:
          return initializeCartDrawerHidingLogicThree();
        case 4:
          return initializeCartDrawerHidingLogicFour();
        case 5:
          return initializeCartDrawerHidingLogicFive();
        default:
          return false;
      }
    };

    // Try selected strategy
    try {
      if (executeStrategy(strategy)) {
        console.log(`✅ Strategy ${strategy} initialized successfully`);
        return;
      }
    } catch (error) {
      console.warn(`Strategy ${strategy} failed:`, error);
    }

    // Fallback to strategy 1 if not already tried
    if (strategy !== 1) {
      try {
        if (executeStrategy(1)) {
          console.log("✅ Fallback to Strategy 1 successful");
          return;
        }
      } catch (error) {
        console.error("Fallback failed:", error);
      }
    }

    console.error("All cart hiding strategies failed");
  }, []);
  const {
    setSettings,
    settings,
    isBlurryPageLoaderEnabled,
    // handleCartCheckPartialPaymentAndPopup,
  } = useOtpStore();

  const {
    partialPaymentEnabled,
    preIsLoginEnabled,
    isPrefilledAddressEnabled,
    isNewDesignEnabled,
    enablePreOrderOtp,
  } = settings;

  const session = getSessionValue("verifiedNumberData");
  const isOtpVerified = !!(session && session.isOTPVerified);
  const [isPreOrderOtpEnabled, setIsPreOrderOtpEnabled] = useState(false);
  const [settingsInitialized, setSettingsInitialized] = useState(false);
  const [client, setClient] = useState(null);

  const initializeSettings = async () => {
    try {
      const enablePreOrderOtp = await syncSessionWithSettings(setSettings);
      setIsPreOrderOtpEnabled((prevState) => {
        debugLog("Previous isPreOrderOtpEnabled:", prevState);
        debugLog("New isPreOrderOtpEnabled:", enablePreOrderOtp);
        return enablePreOrderOtp;
      });
      setSettingsInitialized(true);
    } catch (error) {
      console.error("Error syncing session with settings:", error);
      sendErrorToAPI(error, "OTPManager.syncSessionWithSettings");
    }
  };

  // Apollo Client creation removed - using lightweight GraphQL client instead

  useEffect(() => {
    const settings = getSessionValue("settingSession");
    if (!settings?.storeFrontToken || settings.storeFrontToken.length === 0) {
      console.error("storeFrontToken is invalid or missing.");
      return;
    }

    if (!window.Shopify?.shop) {
      console.error("Shopify domain is not available.");
      return;
    }

    if (settingsInitialized) {
      debugLog(
        "Settings initialized and token available, GraphQL client ready.",
      );
      setClient(true); // Set to true since we don't need Apollo Client instance anymore
    }
  }, [settingsInitialized, settings?.storeFrontToken]);

  useEffect(() => {
    debugLog("isBlurryPageLoaderEnabled .", isBlurryPageLoaderEnabled);
  }, [isBlurryPageLoaderEnabled]);

  // const executePartialPaymentFunctions = async () => {
  //   loadRuleVariantArrayFromSession();
  //   await handleCartCheckPartialPaymentAndPopup();
  //   debugLog("functions executed successfully");
  // };

  const executeLoginFlowFunction = async () => {
    if (!client) {
      console.error("Apollo client is not ready yet.");
      return;
    }
    window.renderDummyComponent = (elementId) => {
      const targetElement = document.getElementById(elementId);
      if (targetElement) {
        ReactDOM.render(
          <OTPWidget onClose={handleCloseModal} />,
          targetElement,
        );
      } else {
        console.error(`Element with ID "${elementId}" not found.`);
      }
    };
  };

  const initializeComponent = async () => {
    const settings = getSessionValue("settingSession");
    try {
      if (settings?.preIsLoginEnabled) {
        debugLog("preIsLoginEnabled", settings?.preIsLoginEnabled);
        await executeLoginFlowFunction();
      }
      // syncSessionWithCart();
    } catch (error) {
      console.error("Error initializing component:", error);
      sendErrorToAPI(error, "OTPManager.initializeComponent");
    }
  };

  useEffect(() => {
    debugLog("OTPManager mounted");
    const init = async () => {
      debugLog("init: calling initializeSettings");
      await initializeSettings();
      debugLog("init: finished initializeSettings");
      debugLog("is otp Verified", isOtpVerified);
    };

    init();
    const handlePageShow = (event) => {
      if (event.persisted) {
        debugLog("Page restored from bfcache. Reloading page.");
        window.location.reload();
      }
    };

    window.addEventListener("pageshow", handlePageShow);
    return () => {
      window.removeEventListener("pageshow", handlePageShow);
    };
  }, []);

  useEffect(() => {
    initializeComponent();
  }, [
    preIsLoginEnabled,
    isPrefilledAddressEnabled,
    isNewDesignEnabled,
    enablePreOrderOtp,
    client,
  ]);

  if (!settingsInitialized || !client) {
    return (
      <PageContainer>
        <LayoutContainer>
          <Section>
            <LoadingContainer>
              <Spinner />
              <LoadingText>Loading...</LoadingText>
            </LoadingContainer>
          </Section>
        </LayoutContainer>
      </PageContainer>
    );
  }

  return (
    <PageContainer>
      <LayoutContainer>
        {(isPreOrderOtpEnabled || partialPaymentEnabled) && (
          <Section>
            <ButtonManager />
          </Section>
        )}
        {isBlurryPageLoaderEnabled && (
          <Section>
            <Banner>
              <BannerIcon>i</BannerIcon>
              <BannerContent>
                <BannerTitle>Loading</BannerTitle>
                <BannerMessage>
                  Cart is processing, please wait...
                </BannerMessage>
              </BannerContent>
            </Banner>
          </Section>
        )}
      </LayoutContainer>
    </PageContainer>
  );
};

export default OTPManager;
