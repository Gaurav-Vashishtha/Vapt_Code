import React, {
  useState,
  useCallback,
  useContext,
  useEffect,
  useRef,
} from "react";
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import {
  Page,
  Banner,
  Badge,
  Icon,
  Box,
  Divider,
  Modal,
  VideoThumbnail,
  ChoiceList,
  EmptyState,
} from "@shopify/polaris";

import Api from "../Services/Api";
import { StoreContext } from "../Context/Store";
import I18n from "../i18n-lang";
import Settings from "./../Components/Settings";
import PreOrderSetting from "./../Components/PreOrderSetting";
import OTPPlacementOptions from "./OTPPlacementOptions";
import PlusCheckoutOtpExtensionSettings from "./PlusCheckoutOtpExtensionSettings";
import { navigateTo } from "../../utils/navigate";
import { currentAppPath } from "../Pages/SettingsHub/hubUrl";

const OTP_ROUTES = {
  COMPARISON: "comparison",
  PRE_ORDER: "pre-order",
  POST_ORDER: "post-order",
  CHECKOUT_EXTENSION: "checkout-extension",
};

/** The pre-order screen with its customization modal open. */
const PRE_ORDER_UI_TAB = 1;
const UI_CUSTOMIZATION_PATHS = ["/features/ui-customization", "/pre-order/ui"];

const isUiCustomizationPath = (pathname) => {
  const path = (pathname || currentAppPath()).replace(/\/+$/, "");
  return UI_CUSTOMIZATION_PATHS.some((suffix) => path.endsWith(suffix));
};

const getPreOrderTabFromPath = (pathname) =>
  isUiCustomizationPath(pathname) ? PRE_ORDER_UI_TAB : 0;

const getOtpRouteFromPath = (pathname) => {
  const path = (pathname || currentAppPath()).replace(/\/+$/, "");
  if (isUiCustomizationPath(path)) return OTP_ROUTES.PRE_ORDER;
  if (path.endsWith("/pre-order")) return OTP_ROUTES.PRE_ORDER;
  if (path.endsWith("/post-order") || path.endsWith("/post-order-otp"))
    return OTP_ROUTES.POST_ORDER;
  if (
    path.endsWith("/checkout-extension") ||
    path.endsWith("/shopify-plus-widget")
  )
    return OTP_ROUTES.CHECKOUT_EXTENSION;
  return OTP_ROUTES.COMPARISON;
};

const SettingWrapper = () => {
  const shopify = useAppBridge(); // Initialize v4 App Bridge
  const {
    banner: [banner, setBanner],
    contextualBar: [contextualBar, setContextualBar],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
  } = useContext(StoreContext);

  const settingRef = useRef(setting);
  const [isDirty, setIsDirty] = useState(false);
  const [pathname, setPathname] = useState(currentAppPath);

  const [isPrefilledEnabled, setIsPrefilledEnabled] = useState(
    setting.isPrefilledAddressEnabled
  );
  const [selectedOtpType, setSelectedOtpType] = useState("");
  const [errorMessage, setErrorMessage] = useState("");
  const [isSaving, setIsSaving] = useState(false);

  const otpRoute = getOtpRouteFromPath(pathname);
  const showRecommendation = otpRoute === OTP_ROUTES.COMPARISON;
  const showPreEnabled = otpRoute === OTP_ROUTES.PRE_ORDER;
  const showPostEnabled = otpRoute === OTP_ROUTES.POST_ORDER;
  const showCheckoutExtension = otpRoute === OTP_ROUTES.CHECKOUT_EXTENSION;

  useEffect(() => {
    let timeout;
    if (banner.active) {
      timeout = setTimeout(() => {
        setBanner((prev) => ({ ...prev, active: false }));
      }, 3000);
    }
    return () => clearTimeout(timeout);
  }, [banner.active]);

  useEffect(() => {
    settingRef.current = setting;
  }, [setting]);

  useEffect(() => {
    setIsDirty(contextualBar);
  }, [contextualBar]);

  useEffect(() => {
    const syncPath = () => setPathname(currentAppPath());
    window.addEventListener("popstate", syncPath);
    window.addEventListener("locationchange", syncPath);
    return () => {
      window.removeEventListener("popstate", syncPath);
      window.removeEventListener("locationchange", syncPath);
    };
  }, []);

  const [enablePreOrderOtp, setPreOrderOtp] = useState(
    setting?.enablePreOrderOtp + ""
  );

  const handleSettingChange = (key) => (value) => {
    if (key === "enablePreOrderOtp") {
      value = value[0];
      setPreOrderOtp(value);
    }
    setSetting({
      ...setting,
      [key]: value,
    });
    !contextualBar && setContextualBar(true);
  };

  const handleOtpTypeSelection = (value) => {
    setSelectedOtpType(value[0]);
  };

  // const handleSetupClick = () => {
  //   if (selectedOtpType === "pre") {
  //     setPreOrderOtp("true");
  //     handleSettingChange("enablePreOrderOtp")(["true"]);
  //   }
  //   setShowRecommendation(false);
  // };

  const handleSetupClick = () => {
    if (selectedOtpType === "pre") {
      navigateTo("/features/otp/pre-order");
    } else if (selectedOtpType === "post") {
      navigateTo("/features/post-order-otp");
    }
  };

  const recommendationClick = (value) => {
    if (value === "pre") {
      navigateTo("/features/otp/pre-order");
    } else {
      navigateTo("/features/post-order-otp");
    }
  };

  const handleSubmit = async () => {
    setErrorMessage("");
    setIsSaving(true);
    Api.post("/settings", settingRef.current)
      .then((res) => {
        setSetting(res.data);
        setOriginalSetting(res.data);
        setContextualBar(false);
        setIsDirty(false);
        shopify.toast.show(I18n.t("admin.settings_saved"));
        setBanner({
          active: true,
          status: "success",
          text: I18n.t("admin.settings_saved"),
        });
      })
      .catch((error) => {
        setContextualBar(false);
        setIsDirty(false);
        shopify.toast.show(error?.response?.data || I18n.t("admin.settings_error"), { isError: true });
        setErrorMessage(
          error?.response?.data || I18n.t("admin.settings_error")
        );
      })
      .finally(() => {
        setIsSaving(false);
      });
  };

  const handleDiscard = () => {
    const cloned = JSON.parse(JSON.stringify(originalSetting));
    setSetting(cloned);
    setIsPrefilledEnabled(cloned.isPrefilledAddressEnabled || "");
    setContextualBar(false);
    setIsDirty(false);
  };

  if (showRecommendation) {
    return (
      <OTPPlacementOptions
        onOtpTypeSelection={handleOtpTypeSelection}
        onSetupClick={handleSetupClick}
        selectedOtpType={selectedOtpType}
      />
    );
  }

  // Dynamic title and subtitle based on route
  const getPageTitle = () => {
    if (showCheckoutExtension)
      return I18n.t("admin.plus_checkout_extension_page_title");
    // The sidebar item and the page it opens should read the same.
    if (isUiCustomizationPath(pathname))
      return I18n.t("pre_order.ui_customization");
    if (showPreEnabled) return I18n.t("pre_order.pre_order_otp_setup");
    if (showPostEnabled) return I18n.t("post_order.page_title");
    return I18n.t("admin.otp_settings_title");
  };

  const getPageSubtitle = () => {
    if (showCheckoutExtension)
      return I18n.t("admin.plus_checkout_extension_page_subtitle");
    if (isUiCustomizationPath(pathname))
      return I18n.t("pre_order.ui_customization_subtitle");
    if (showPreEnabled) return I18n.t("pre_order.setup_subtitle");
    if (showPostEnabled) return I18n.t("post_order.setup_subtitle");
    return I18n.t("admin.otp_settings_subtitle");
  };

  // Shopify-like: when there are unsaved changes, in-app back button does nothing (no alert, no navigation)
  const handleBackToComparison = () => {
    if (contextualBar || isDirty) return;
    navigateTo("/features/otp");
  };

  return (
    <Page
      title={getPageTitle()}
      subtitle={getPageSubtitle()}
      fullWidth={true}
    >
      {/* App Bridge v4 SaveBar */}
      <SaveBar data-save-bar open={isDirty}>
        <button
          variant="primary"
          onClick={handleSubmit}
          loading={isSaving ? "" : undefined}
          disabled={isSaving}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>
          {I18n.t("admin.discard")}
        </button>
      </SaveBar>
      {banner.active && (
        <Box paddingBlockEnd="400">
          <Banner
            title={banner.text}
            status={banner.status}
            onDismiss={() => setBanner({ ...banner, active: false })}
          />
        </Box>
      )}

      {errorMessage && (
        <Box paddingBlockEnd="400">
          <Banner
            title={I18n.t("admin.settings_error")}
            status="critical"
            onDismiss={() => setErrorMessage("")}
          >
            <p>{errorMessage}</p>
          </Banner>
        </Box>
      )}

      {!showRecommendation && (
        <>
          {showCheckoutExtension ? (
            <PlusCheckoutOtpExtensionSettings />
          ) : showPreEnabled ? (
            <PreOrderSetting
              onBackToSettings={handleBackToComparison}
              activeTab={getPreOrderTabFromPath(pathname)}
            />
          ) : (
            <Settings onBackToSettings={handleBackToComparison} />
          )}
        </>
      )}
    </Page>
  );
};

export default SettingWrapper;
