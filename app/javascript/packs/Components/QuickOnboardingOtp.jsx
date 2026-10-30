import React, {
  useState,
  useContext,
  useEffect,
  useRef,
  useCallback,
} from "react";
import styled, { keyframes } from "styled-components";
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import { navigateTo } from "../../utils/navigate";
import {
  Card,
  Button,
  BlockStack,
  Checkbox,
  Text,
  Box,
  InlineStack,
  Badge,
  Banner,
  Spinner,
  Icon,
  Tooltip,
  ProgressBar,
  Page,
} from "@shopify/polaris";

// Updated icon imports - only using icons available in @shopify/polaris-icons
import { ChevronLeftMinor } from "@shopify/polaris-icons";

import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";
import QuickBilling from "./QuickBilling";
import QuickCurrentStep from "./QuickCurrentStep";
import PostOrderOTPWizard from "./PostOrderOTPWizard";
import Settings from "./Settings";
import OTPPlacementOptions from "./OTPPlacementOptions";
import I18n from "../i18n-lang";
import PreOrderSetting from "./PreOrderSetting";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";

// Constants
const STEP = {
  SELECT_OTP_TYPE: 1,
  ACTIVATE_OTP: 2,
  BILLING: 3,
};

const OTP_TYPE = {
  NONE: "",
  PRE_ORDER: "pre_order",
  POST_ORDER: "post_order",
};

const POLLING_INTERVAL = 3000; // 3 seconds
const MAX_POLLING_ATTEMPTS = 20; // Max 1 minute of polling

// Animations
const fadeIn = keyframes`
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
`;

const pulse = keyframes`
  0% { transform: scale(1); }
  50% { transform: scale(1.05); }
  100% { transform: scale(1); }
`;

const slideIn = keyframes`
  from { transform: translateX(-100%); opacity: 0; }
  to { transform: translateX(0); opacity: 1; }
`;

// Styled Components
const Container = styled.div`
  max-width: 960px;
  margin: 32px auto;
  background: white;
  border: 1px solid #e1e3e5;
  border-radius: 16px;
  padding: 32px;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
  position: relative;
  animation: ${fadeIn} 0.3s ease-out;

  @media (max-width: 768px) {
    margin: 16px;
    padding: 20px;
  }
`;

const HeaderSection = styled.div`
  text-align: center;
  margin-bottom: 32px;
`;

const Title = styled.h1`
  font-size: 24px;
  font-weight: 700;
  color: #202223;
  margin: 0 0 8px 0;
  letter-spacing: -0.3px;
`;

const Subtitle = styled.p`
  font-size: 14px;
  color: #6d7175;
  margin: 0;
`;

const WizardContainer = styled.div`
  background: #f9fafb;
  border-radius: 12px;
  padding: 20px;
  margin-bottom: 32px;
`;

const WizardSteps = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  max-width: 600px;
  margin: 0 auto;
`;

const Step = styled.div`
  display: flex;
  align-items: center;
  flex: 1;
  position: relative;

  &:not(:last-child)::after {
    content: "";
    position: absolute;
    top: 50%;
    left: calc(50% + 40px);
    right: calc(-50% + 40px);
    height: 2px;
    background: ${(props) => (props.completed ? "#008060" : "#e1e3e5")};
    transform: translateY(-50%);
    transition: background 0.3s ease;
  }
`;

const StepContent = styled.div`
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  flex: 1;
  z-index: 1;
`;

const StepCircle = styled.div`
  background-color: ${(props) => (props.active ? "#3b82f6" : "#e5e7eb")};
  color: white;
  width: 20px;
  height: 20px;
  font-size: 12px;
  border-radius: 50%;
  display: flex;
  justify-content: center;
  align-items: center;
  margin-right: 6px;
`;

const StepLabel = styled.div`
  font-size: 12px;
  font-weight: ${(props) => (props.active ? "600" : "500")};
  color: ${(props) => (props.active ? "#202223" : "#6d7175")};
  white-space: nowrap;
`;

const SelectableCard = styled.div`
  background: ${(props) => (props.disabled ? "#f9fafb" : "white")};
  border: 2px solid
    ${(props) =>
      props.selected ? "#008060" : props.disabled ? "#e1e3e5" : "#e1e3e5"};
  border-radius: 12px;
  padding: 24px;
  cursor: ${(props) => (props.disabled ? "not-allowed" : "pointer")};
  opacity: ${(props) => (props.disabled ? 0.6 : 1)};
  transition: all 0.2s ease;
  position: relative;
  overflow: hidden;

  ${(props) =>
    !props.disabled &&
    `
    &:hover {
      border-color: ${props.selected ? "#008060" : "#8c9196"};
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
      transform: translateY(-2px);
    }
  `}

  ${(props) =>
    props.selected &&
    `
    background: linear-gradient(135deg, #f0fdf4 0%, #ffffff 100%);
    box-shadow: 0 0 0 3px rgba(0, 128, 96, 0.1);
  `}

  animation: ${fadeIn} 0.3s ease-out;
`;

const CardIcon = styled.div`
  width: 40px;
  height: 40px;
  background: ${(props) => (props.selected ? "#008060" : "#f6f6f7")};
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 16px;
  transition: all 0.2s ease;

  svg {
    fill: ${(props) => (props.selected ? "white" : "#5c5f62")};
  }
`;

const CardTitle = styled.h3`
  font-size: 16px;
  font-weight: 600;
  color: #202223;
  margin: 0 0 8px 0;
`;

const CardDescription = styled.p`
  font-size: 13px;
  color: #6d7175;
  margin: 0;
  line-height: 1.5;
`;

const ComingSoonBadge = styled.div`
  position: absolute;
  top: 12px;
  right: 12px;
  background: #f3f3f3;
  color: #8c9196;
  font-size: 11px;
  font-weight: 600;
  padding: 4px 8px;
  border-radius: 4px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
`;

const StepCard = styled(Card)`
  margin-bottom: 16px;
  animation: ${slideIn} 0.3s ease-out;
  animation-delay: ${(props) => props.delay || "0s"};
  animation-fill-mode: both;
`;

const StatusIndicator = styled.div`
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 4px 12px;
  border-radius: 6px;
  background: ${(props) => (props.success ? "#e3f5e1" : "#fef3e2")};
  color: ${(props) => (props.success ? "#008060" : "#b98900")};
  font-size: 13px;
  font-weight: 500;
`;

const TestButton = styled(Button)`
  animation: ${(props) => (props.highlight ? pulse : "none")} 2s infinite;
`;

const BenefitsBox = styled(Box)`
  background: linear-gradient(135deg, #f0fdf4 0%, #e3f5e1 100%);
  border: 1px solid #008060;
  border-radius: 8px;
  padding: 16px;
`;

// Error Boundary Component
class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true };
  }

  componentDidCatch(error, errorInfo) {
    console.error("Onboarding Error:", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <Banner
          title={I18n.t("onboarding_otp.error.title")}
          tone="critical"
          action={{
            content: I18n.t("onboarding_otp.error.reload"),
            onAction: () => window.location.reload(),
          }}
        >
          <p>{I18n.t("onboarding_otp.error.message")}</p>
        </Banner>
      );
    }

    return this.props.children;
  }
}

// Main Component
function QuickOnboardingOtp() {
  // State Management
  const [step, setStep] = useState(STEP.SELECT_OTP_TYPE);
  const [selectedOtpType, setSelectedOtpType] = useState(OTP_TYPE.NONE);
  const [isExtensionEnabled, setIsExtensionEnabled] = useState(false);
  const [extensionStatusLoading, setExtensionStatusLoading] = useState(true);
  const [productUrlData, setProductUrlData] = useState(null);
  const [productUrlLoading, setProductUrlLoading] = useState(true);
  const [pollingAttempts, setPollingAttempts] = useState(0);
  const [error, setError] = useState(null);
  const [isSaving, setIsSaving] = useState(false);

  // Refs
  const pollingRef = useRef(null);
  const mounted = useRef(true);
  const settingRef = useRef(null);
  const shopify = useAppBridge(); // Initialize v4 App Bridge

  // Context
  const {
    shop: [shop],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    contextualBar: [contextualBar, setContextualBar],
    tab: [, setTab],
  } = useContext(StoreContext);

  /**
   * App Bridge v4 Navigation Interceptor
   * Prevents full page reload and syncs with Shopify Admin
   */
  const handleRedirect = (e, path) => {
    if (e) e.preventDefault();

    // 1. Update the address bar without hitting the server
    window.history.pushState({}, "", path);

    // 2. Dispatch event so StoreProvider/Router can update the view
    const navEvent = new PopStateEvent("popstate");
    window.dispatchEvent(navEvent);

    // 3. If your StoreContext uses a setTab function for routing, call it here
    if (typeof setTab === "function") {
      setTab(path);
    }
  };

  // User Journey Tracker
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  // Keep settingRef in sync with current setting
  useEffect(() => {
    settingRef.current = setting;
  }, [setting]);

  const [pathname, setPathname] = useState(window.location.pathname);

  const otpRoute = (() => {
    const path = (pathname || "").replace(/\/+$/, "");
    if (path.endsWith("/pre-order")) return { step: STEP.ACTIVATE_OTP, type: OTP_TYPE.PRE_ORDER };
    if (path.endsWith("/post-order")) return { step: STEP.ACTIVATE_OTP, type: OTP_TYPE.POST_ORDER };
    return { step: STEP.SELECT_OTP_TYPE, type: selectedOtpType };
  })();

  const effectiveStep = otpRoute.step;
  const effectiveOtpType = otpRoute.type === OTP_TYPE.PRE_ORDER || otpRoute.type === OTP_TYPE.POST_ORDER
    ? otpRoute.type
    : selectedOtpType;

  useEffect(() => {
    const syncPath = () => setPathname(window.location.pathname);
    window.addEventListener("popstate", syncPath);
    window.addEventListener("locationchange", syncPath);
    return () => {
      window.removeEventListener("popstate", syncPath);
      window.removeEventListener("locationchange", syncPath);
    };
  }, []);

  useEffect(() => {
    if (effectiveStep === STEP.ACTIVATE_OTP && effectiveOtpType !== selectedOtpType) {
      setSelectedOtpType(effectiveOtpType);
    }
  }, [effectiveStep, effectiveOtpType]);

  // Track page load
  useEffect(() => {
    journeyTracker.trackPageLoad({
      step: effectiveStep,
      selectedOtpType: effectiveOtpType || selectedOtpType,
      isExtensionEnabled: isExtensionEnabled,
    });
  }, [pathname]);

  const [isDirty, setIsDirty] = useState(false);

  // Track isDirty based on contextualBar
  useEffect(() => {
    setIsDirty(contextualBar);
  }, [contextualBar]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      mounted.current = false;
      if (pollingRef.current) {
        clearInterval(pollingRef.current);
      }
    };
  }, []);

  // Check Extension Status
  const checkExtensionStatus = useCallback(async () => {
    if (!shop?.shopify_domain) return;

    setExtensionStatusLoading(true);
    setError(null);

    try {
      const url = `https://${process.env.APP_HOST}/order_confirmations/is_cod_king_block_enabled?shopifyDomain=${shop.shopify_domain}`;
      const response = await fetch(url);

      if (!response.ok)
        throw new Error(I18n.t("onboarding_otp.error.extension_status_error"));

      const data = await response.json();

      if (mounted.current) {
        setIsExtensionEnabled(data.assetEnabled);

        if (data.assetEnabled && pollingRef.current) {
          clearInterval(pollingRef.current);
          pollingRef.current = null;
          setPollingAttempts(0);
        }
      }
    } catch (err) {
      console.error(
        I18n.t("onboarding_otp.error.extension_status_check_error"),
        err,
      );
      if (mounted.current) {
        setError(
          I18n.t("onboarding_otp.error.extension_status_check_error_message"),
        );
      }
    } finally {
      if (mounted.current) {
        setExtensionStatusLoading(false);
      }
    }
  }, [shop?.shopify_domain]);

  // Start polling for extension status
  const startPolling = useCallback(() => {
    if (pollingRef.current) return;

    setPollingAttempts(0);
    pollingRef.current = setInterval(() => {
      setPollingAttempts((prev) => {
        if (prev >= MAX_POLLING_ATTEMPTS) {
          clearInterval(pollingRef.current);
          pollingRef.current = null;
          return prev;
        }
        checkExtensionStatus();
        return prev + 1;
      });
    }, POLLING_INTERVAL);
  }, [checkExtensionStatus]);

  // Fetch product URL
  useEffect(() => {
    Api.get("/settings/product_url")
      .then((res) => {
        if (mounted.current) {
          // Check if response has error or no product_url
          if (res.data?.error || !res.data?.product_url) {
            console.warn(
              I18n.t("onboarding_otp.error.product_url_fetch_error"),
              res.data?.message || "No product URL available",
            );
            setProductUrlData({
              error: true,
              message: res.data?.message || "No active products found",
            });
          } else {
            setProductUrlData(res.data);
          }
          setProductUrlLoading(false);
        }
      })
      .catch((err) => {
        console.error(
          I18n.t("onboarding_otp.error.product_url_fetch_error"),
          err,
        );
        if (mounted.current) {
          setProductUrlData({
            error: true,
            message:
              err.response?.data?.message || "Failed to fetch product URL",
          });
          setProductUrlLoading(false);
        }
      });
  }, []);

  // Initial extension status check
  useEffect(() => {
    checkExtensionStatus();
  }, [checkExtensionStatus]);

  // Handle Pre-OTP toggle
  const togglePreOtp = useCallback(
    (value) => {
      setSetting((prev) => ({ ...prev, enablePreOrderOtp: value }));
      setContextualBar(true);

      // Track setting change
      journeyTracker.trackSettingChange("enablePreOrderOtp", !value, value, {
        step: step,
        selectedOtpType: selectedOtpType,
      });
    },
    [setSetting, setContextualBar, step, selectedOtpType],
  );

  // Save settings
  const handleSave = useCallback(async () => {
    setIsSaving(true);
    setError(null);

    try {
      await Api.post("/settings", settingRef.current);
      setOriginalSetting(settingRef.current);
      setContextualBar(false);
      setIsDirty(false);
      shopify.toast.show(I18n.t("admin.settings_saved"));

      // Track successful save
      journeyTracker.trackFormSubmit("otp_settings", settingRef.current, {
        step: step,
        selectedOtpType: selectedOtpType,
      });
    } catch (err) {
      console.error(I18n.t("onboarding_otp.error.save_error"), err);
      setError(I18n.t("onboarding_otp.error.save_error_message"));
      shopify.toast.show(I18n.t("onboarding_otp.error.save_error_message"), {
        isError: true,
      });

      // Track save error
      journeyTracker.trackError("save_error", err.message, {
        step: step,
        selectedOtpType: selectedOtpType,
      });
    } finally {
      setIsSaving(false);
    }
  }, [
    setOriginalSetting,
    setContextualBar,
    journeyTracker,
    step,
    selectedOtpType,
    shopify,
  ]);

  // Discard changes
  const handleDiscard = useCallback(() => {
    const cloned = JSON.parse(JSON.stringify(originalSetting));
    setSetting(cloned);
    setContextualBar(false);
    setIsDirty(false);

    // Track discard action
    journeyTracker.trackButtonClick("discard_changes", {
      step: step,
      selectedOtpType: selectedOtpType,
    });
  }, [
    originalSetting,
    setSetting,
    setContextualBar,
    journeyTracker,
    step,
    selectedOtpType,
  ]);

  // Open theme editor
  const openThemeEditor = useCallback(() => {
    const url = `https://${shop?.shopify_domain}/admin/themes/current/editor?context=apps&template=cart&activateAppId=99553eb5-bf07-4ce0-9263-7e5f10cab22c/app-embed`;
    window.open(url, "_blank", "noopener,noreferrer");
    startPolling();

    // Track theme editor opening
    journeyTracker.trackButtonClick("open_theme_editor", {
      step: step,
      selectedOtpType: selectedOtpType,
      url: url,
    });
  }, [
    shop?.shopify_domain,
    startPolling,
    journeyTracker,
    step,
    selectedOtpType,
  ]);

  // Progress calculation (based on route)
  const progressValue =
    effectiveStep === STEP.SELECT_OTP_TYPE
      ? 33
      : effectiveStep === STEP.ACTIVATE_OTP
        ? 66
        : 100;

  // Dynamic title based on current step (route)
  const getPageTitle = () => {
    if (effectiveStep === STEP.SELECT_OTP_TYPE) {
      return I18n.t("onboarding_otp.select_otp_type_title");
    }
    if (effectiveStep === STEP.ACTIVATE_OTP) {
      if (effectiveOtpType === OTP_TYPE.PRE_ORDER) {
        return I18n.t("onboarding_otp.pre_order_setup_title");
      }
      if (effectiveOtpType === OTP_TYPE.POST_ORDER) {
        return I18n.t("onboarding_otp.post_order_setup_title");
      }
    }
    return I18n.t("onboarding_otp.page_title");
  };

  // Dynamic subtitle based on current step (route)
  const getPageSubtitle = () => {
    if (effectiveStep === STEP.SELECT_OTP_TYPE) {
      return I18n.t("onboarding_otp.select_otp_type_subtitle");
    }
    if (effectiveStep === STEP.ACTIVATE_OTP) {
      if (effectiveOtpType === OTP_TYPE.PRE_ORDER) {
        return I18n.t("onboarding_otp.pre_order_setup_subtitle");
      }
      if (effectiveOtpType === OTP_TYPE.POST_ORDER) {
        return I18n.t("onboarding_otp.post_order_setup_subtitle");
      }
    }
    return I18n.t("onboarding_otp.page_subtitle");
  };

  // Shopify-like: when there are unsaved changes, in-app back button does nothing (no alert, no navigation)
  const hasUnsavedChanges = contextualBar || isDirty;
  const getBackAction = () => {
    if (effectiveStep === STEP.SELECT_OTP_TYPE) {
      return {
        content: I18n.t("onboarding_otp.back_to_onboarding"),
        onAction: (e) => {
          if (hasUnsavedChanges) return;
          handleRedirect(e, "/quick-onboarding");
        },
      };
    }
    if (effectiveStep === STEP.ACTIVATE_OTP) {
      return {
        content: I18n.t("onboarding_otp.back_to_selection"),
        onAction: () => {
          if (hasUnsavedChanges) return;
          journeyTracker.trackButtonClick("back_to_selection", {
            fromStep: effectiveStep,
            toStep: STEP.SELECT_OTP_TYPE,
          });
          navigateTo("/quick-onboarding/otp");
        },
      };
    }
    return {
      content: I18n.t("onboarding_otp.back_to_onboarding"),
      onAction: (e) => {
        if (hasUnsavedChanges) return;
        handleRedirect(e, "/quick-onboarding");
      },
    };
  };

  return (
    <Page
      title={getPageTitle()}
      subtitle={getPageSubtitle()}
      backAction={getBackAction()}
      fullWidth={true}
    >
      {/* App Bridge v4 SaveBar */}
      <SaveBar data-save-bar open={isDirty}>
        <button
          variant="primary"
          onClick={handleSave}
          loading={isSaving ? "" : undefined}
          disabled={isSaving}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>{I18n.t("admin.discard")}</button>
      </SaveBar>
      <ErrorBoundary>
        {error && (
          <Box marginBlockEnd="400">
            <Banner tone="critical" onDismiss={() => setError(null)}>
              <p>{error}</p>
            </Banner>
          </Box>
        )}

        {/* Step 1: Select OTP Type (comparison) */}
        {effectiveStep === STEP.SELECT_OTP_TYPE && (
          <OTPPlacementOptions
            isOnboardingFlow={true}
            onOtpTypeSelection={(value) => {
              const v = value[0];
              const otpType =
                v === "pre"
                  ? OTP_TYPE.PRE_ORDER
                  : v === "post"
                    ? OTP_TYPE.POST_ORDER
                    : OTP_TYPE.NONE;
              setSelectedOtpType(otpType);

              journeyTracker.trackButtonClick("otp_type_selection", {
                selectedType: otpType,
                step: step,
              });
            }}
            onSetupClick={() => {
              journeyTracker.trackButtonClick("setup_otp", {
                fromStep: effectiveStep,
                toStep: STEP.ACTIVATE_OTP,
                selectedOtpType: selectedOtpType,
              });
              if (selectedOtpType === OTP_TYPE.PRE_ORDER) {
                navigateTo("/quick-onboarding/otp/pre-order");
              } else if (selectedOtpType === OTP_TYPE.POST_ORDER) {
                navigateTo("/quick-onboarding/otp/post-order");
              }
            }}
            selectedOtpType={
              selectedOtpType === OTP_TYPE.PRE_ORDER
                ? "pre"
                : selectedOtpType === OTP_TYPE.POST_ORDER
                  ? "post"
                  : ""
            }
            hideBackAction={true}
          />
        )}

        {/* Step 2: Activate & Test */}
        {effectiveStep === STEP.ACTIVATE_OTP &&
          effectiveOtpType === OTP_TYPE.PRE_ORDER && (
            <PreOrderSetting isOnboardingFlow={true} />
          )}
        {effectiveStep === STEP.ACTIVATE_OTP &&
          effectiveOtpType === OTP_TYPE.POST_ORDER && (
            <Settings isOnboardingFlow={true} />
          )}
      </ErrorBoundary>
    </Page>
  );
}

export default QuickOnboardingOtp;
