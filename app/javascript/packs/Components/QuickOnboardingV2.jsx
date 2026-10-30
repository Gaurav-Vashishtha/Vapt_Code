import React, {
  useState,
  useCallback,
  useEffect,
  useRef,
  useContext,
} from "react";
import {
  Page,
  Card,
  BlockStack,
  InlineStack,
  InlineGrid,
  Text,
  Button,
  Checkbox,
  Banner,
  Select,
  ProgressBar,
  Box,
  Badge,
  Spinner,
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
  Divider,
  Link,
  Collapsible,
  useBreakpoints,
  Modal,
  Scrollable,
  TextField,
  Tooltip,
} from "@shopify/polaris";
import {
  RefreshMinor,
  ExternalMinor,
  ArrowLeftMinor,
} from "@shopify/polaris-icons";
import { StoreContext } from "../Context/Store";
import LanguageDropdown from "./Integrations/LanguageDropdown";
import I18n from "../i18n-lang";
import Api from "../Services/Api";
import {
  useWhatsappLanguages,
  WhatsappLanguagePicker,
  WhatsappNotificationPreview,
  WA_PREVIEW_EVENTS,
  saveWhatsappLanguage,
} from "./WhatsappLanguage/WhatsappLanguage.jsx";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";
import { markCustomSetupPendingAfterBilling } from "../utils/customSetupFlow";
import WidgetPreviewPanel from "./WidgetPreview/WidgetPreviewPanel";
import OnboardingSetupStep from "../Pages/CodForm/components/OnboardingSetupStep";
import OnboardingFormPreview, { useCodFormOn } from "../Pages/CodForm/components/OnboardingFormPreview";
import useCodFormBootstrap from "../Pages/CodForm/useCodFormBootstrap";
import OnboardingEmbedStep from "../Pages/CodForm/components/OnboardingEmbedStep";
import AppEmbedTutorial from "./AppEmbedTutorial";

// Checkbox that shows a short feature description on hover. The wrapping div is
// the Tooltip activator (Polaris needs a real element to anchor to).
const FeatureCheckbox = ({ tooltip, ...props }) =>
  tooltip ? (
    <Tooltip content={tooltip} dismissOnMouseOut>
      <div>
        <Checkbox {...props} />
      </div>
    </Tooltip>
  ) : (
    <Checkbox {...props} />
  );

const ONBOARDING_STEP_KEY = "cod_king_quick_onboarding_step";

// Same preview images as NotificationSettingsTab (customer SMS/WhatsApp rows)
const CUSTOMER_NOTIF_PREVIEW_ORDER_PLACED =
  "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/x4SVNU.png?v=1701069271";
const CUSTOMER_NOTIF_PREVIEW_FULFILLMENT =
  "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/b.png?v=1701082382";
const CUSTOMER_NOTIF_PREVIEW_ABANDONED_CART =
  "https://cdn.shopify.com/s/files/1/0655/2089/4070/files/whatsapp_abandon_preview.png?v=1774873052";
const CUSTOMER_NOTIF_PREVIEW_COD_VERIFICATION =
  "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/WhatsApp_Image_2025-11-04_at_12.39.52_PM.jpg?v=1762247089";

/** Sample values for {{name}} / %{name} placeholders in SMS templates (onboarding preview only). */
function buildSmsPreviewWithDummies(template, shopDisplayName) {
  const store = shopDisplayName || "Demo Store";
  const defaults = {
    store,
    store_name: store,
    shop: store,
    number: "1234",
    order_number: "1234",
    order_id: "1234",
    orderid: "1234",
    tracking_url: "https://example.com/track/abc",
    tracking_number: "TRK-998877",
    tracking: "TRK-998877",
    link: "https://example.com/order/1234",
    url: "https://example.com/order/1234",
    customer: "Alex Kumar",
    name: "Alex Kumar",
    first_name: "Alex",
    firstname: "Alex",
    amount: "2000 INR",
    total: "2000 INR",
    price: "2000 INR",
    currency: "INR",
    discount: "10%",
    discount_code: "SAVE10",
    phone: "+91 98765 43210",
  };

  const lookup = (rawKey) => {
    const k = String(rawKey)
      .trim()
      .toLowerCase()
      .replace(/\s+/g, "_");
    if (Object.prototype.hasOwnProperty.call(defaults, k)) return defaults[k];
    const snake = k.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase();
    if (Object.prototype.hasOwnProperty.call(defaults, snake)) return defaults[snake];
    return `[${String(rawKey).trim()}]`;
  };

  let out = String(template || "").trim();
  if (!out) return `Thanks for your order on ${store}. Order #1234 is placed.`;
  out = out.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, raw) => lookup(raw));
  out = out.replace(/%\{\s*([^}]+?)\s*\}/g, (_, raw) => lookup(raw));
  return out.trim();
}

/** Notification previews for step 4. The checkout widget is already previewed live on step 2. */
function collectStep4PreviewItems({
  smsConfirmation,
  smsFulfilment,
  smsAbandoned,
  waConfirmation,
  waFulfilment,
  waAbandoned,
  waCodVerification,
  setting,
  shopPreviewName,
}) {
  const items = [];

  if (waConfirmation) {
    items.push({
      id: "wa_order_placed",
      waEvent: WA_PREVIEW_EVENTS.orderConfirmation,
      primaryRank: 10,
      kind: "image",
      captionKey: "quick_onboarding_v2.preview_caption_wa_order_placed",
      src: CUSTOMER_NOTIF_PREVIEW_ORDER_PLACED,
      altKey: "quick_onboarding_v2.preview_alt_order_placed",
    });
  }
  if (waFulfilment) {
    items.push({
      id: "wa_fulfillment",
      waEvent: WA_PREVIEW_EVENTS.fulfilment,
      primaryRank: 11,
      kind: "image",
      captionKey: "quick_onboarding_v2.preview_caption_wa_fulfillment",
      src: CUSTOMER_NOTIF_PREVIEW_FULFILLMENT,
      altKey: "quick_onboarding_v2.preview_alt_fulfillment",
    });
  }
  if (waAbandoned) {
    items.push({
      id: "wa_abandoned",
      waEvent: WA_PREVIEW_EVENTS.abandonedCart,
      primaryRank: 12,
      kind: "image",
      captionKey: "quick_onboarding_v2.preview_caption_wa_abandoned",
      src: CUSTOMER_NOTIF_PREVIEW_ABANDONED_CART,
      altKey: "quick_onboarding_v2.preview_alt_abandoned_cart",
    });
  }
  if (waCodVerification) {
    items.push({
      id: "wa_cod_verification",
      waEvent: WA_PREVIEW_EVENTS.codVerification,
      primaryRank: 13,
      kind: "image",
      captionKey: "quick_onboarding_v2.preview_caption_wa_cod_verification",
      src: CUSTOMER_NOTIF_PREVIEW_COD_VERIFICATION,
      altKey: "quick_onboarding_v2.preview_alt_cod_verification",
    });
  }

  if (smsConfirmation) {
    const raw =
      setting?.orderConfirmationTemplate ||
      process.env.CONFIRMATION_TEMPLATE ||
      "";
    items.push({
      id: "sms_order_placed",
      primaryRank: 20,
      kind: "sms",
      captionKey: "quick_onboarding_v2.sms_preview_order_placed",
      body: buildSmsPreviewWithDummies(raw, shopPreviewName),
    });
  }
  if (smsFulfilment) {
    const raw =
      setting?.fulfilmentTemplate ||
      I18n.t("admin.fulfilment_template_placeholder");
    items.push({
      id: "sms_fulfillment",
      primaryRank: 21,
      kind: "sms",
      captionKey: "quick_onboarding_v2.sms_preview_fulfillment",
      body: buildSmsPreviewWithDummies(raw, shopPreviewName),
    });
  }
  if (smsAbandoned) {
    const raw =
      setting?.abandonedTemplate || I18n.t("admin.sms_placeholder");
    items.push({
      id: "sms_abandoned",
      primaryRank: 22,
      kind: "sms",
      captionKey: "quick_onboarding_v2.sms_preview_abandoned_cart",
      body: buildSmsPreviewWithDummies(raw, shopPreviewName),
    });
  }

  return items;
}

function pickPrimaryPreviewItem(items) {
  return items.reduce((best, cur) =>
    cur.primaryRank < best.primaryRank ? cur : best,
  );
}

const QuickOnboardingV2 = () => {
  const {
    shop: shopState,
    tab: tabState,
    setting: settingState,
  } = useContext(StoreContext);
  const [shop, setShop] = shopState || [{}, () => {}];
  const [, setTab] = tabState || [null, () => {}];
  const [setting, setSetting] = settingState || [{}, () => {}];
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  // WhatsApp message language: options/previews, and the country default during onboarding.
  const { data: waLanguages, reload: reloadWaLanguages } = useWhatsappLanguages();
  const waLanguage = setting?.whatsappLanguageCode || "en";
  const waLanguageSuggestedRef = useRef(false);
  useEffect(() => {
    if (waLanguageSuggestedRef.current || !waLanguages) return;
    waLanguageSuggestedRef.current = true;
    const suggested = waLanguages.suggested;
    // Only for merchants who haven't picked a language themselves and are still on English.
    if (
      waLanguages.ownNumber ||
      waLanguages.selectedByMerchant ||
      !suggested ||
      suggested === "en" ||
      waLanguage !== "en"
    ) {
      return;
    }
    saveWhatsappLanguage(suggested, { suggested: true })
      .then((result) => {
        setSetting((current) => ({ ...current, whatsappLanguageCode: result.language }));
        reloadWaLanguages();
      })
      .catch((err) => console.error("Error applying suggested WhatsApp language:", err));
  }, [waLanguages, setSetting, waLanguage, reloadWaLanguages]);

  const handleWhatsappLanguageChange = useCallback(
    (value) => {
      const previous = waLanguage;
      setSetting((current) => ({ ...current, whatsappLanguageCode: value }));
      journeyTracker.trackEvent("whatsapp_language_changed", { step: 4, language: value });
      saveWhatsappLanguage(value)
        .then(() => reloadWaLanguages())
        .catch((err) => {
          console.error("Error saving WhatsApp language:", err);
          setSetting((current) => ({ ...current, whatsappLanguageCode: previous }));
        });
    },
    [waLanguage, setSetting, journeyTracker, reloadWaLanguages],
  );
  // The COD Form is a feature of its own: it can be the only thing picked on step 2.
  const codFormOn = useCodFormOn();
  const codFormLoaded = useCodFormBootstrap() !== null;
  // Whether the "COD Form" app embed is on in the theme (reported by the theme step).
  const [codFormEmbedOn, setCodFormEmbedOn] = useState(false);
  // The older embed, told apart from the COD Form embed (null = not known yet). The plain
  // theme check below answers "any COD King embed is on", which is wrong once there are two.
  const [legacyEmbedExact, setLegacyEmbedExact] = useState(null);
  const onCodFormEmbedStatus = useCallback((on, legacy) => {
    setCodFormEmbedOn(on);
    setLegacyEmbedExact(legacy === true || legacy === false ? legacy : null);
  }, []);
  const codFormOnRef = useRef(codFormOn);
  codFormOnRef.current = codFormOn;
  const codFormEmbedOnRef = useRef(codFormEmbedOn);
  codFormEmbedOnRef.current = codFormEmbedOn;
  const [currentStep, setCurrentStep] = useState(() => {
    try {
      const saved = sessionStorage.getItem(ONBOARDING_STEP_KEY);
      const n = parseInt(saved, 10);
      return n >= 1 && n <= 4 ? n : 1;
    } catch {
      return 1;
    }
  });
  const [isLoading, setIsLoading] = useState(true);

  // Persist step so returning from billing (or any route) shows the same step
  useEffect(() => {
    try {
      sessionStorage.setItem(ONBOARDING_STEP_KEY, String(currentStep));
    } catch (_) {}
  }, [currentStep]);

  const [otpVerificationEnabled, setOtpVerificationEnabled] = useState(false);
  const [partialPaymentEnabled, setPartialPaymentEnabled] = useState(false);
  const [smsConfirmation, setSmsConfirmation] = useState(false);
  const [smsFulfilment, setSmsFulfilment] = useState(false);
  const [smsAbandoned, setSmsAbandoned] = useState(false);
  const [waConfirmation, setWaConfirmation] = useState(false);
  const [waFulfilment, setWaFulfilment] = useState(false);
  const [waAbandoned, setWaAbandoned] = useState(false);
  const [waCodVerification, setWaCodVerification] = useState(false);
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const [allPreviewsModalOpen, setAllPreviewsModalOpen] = useState(false);
  const { mdUp } = useBreakpoints({ defaults: { mdUp: true } });

  // Step 4 "try it now" test notification (the aha moment before billing).
  const [testPhone, setTestPhone] = useState("");
  const [testLoadingMode, setTestLoadingMode] = useState(null); // 'sms' | 'whatsapp' | null
  const [testBanner, setTestBanner] = useState(null); // { tone, title, message }

  /**
   * App Bridge v4 Navigation Interceptor
   * Prevents full page reload and syncs with Shopify Admin
   */
  const handleRedirect = useCallback(
    (e, path) => {
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
    },
    [setTab],
  );

  // Theme integration states
  const [isExtensionEnabled, setIsExtensionEnabled] = useState(false);
  const [isCheckingTheme, setIsCheckingTheme] = useState(false);
  const [isRefreshingTheme, setIsRefreshingTheme] = useState(false);
  const [themeCheckInterval, setThemeCheckInterval] = useState(null);
  // True once auto-detection polling finished without finding the embed (offer help + skip).
  const [themeCheckTimedOut, setThemeCheckTimedOut] = useState(false);
  const checkCountRef = useRef(0);

  const progressValues = {
    1: 25,
    2: 50,
    3: 75,
    4: 90,
    5: 100,
  };

  // Get shop domain with fallbacks
  const shopDomain =
    shop?.shopify_domain || window.shopOrigin || window.Shopify?.shop || "";

  // Check theme integration status
  const checkThemeIntegration = useCallback(async () => {
    try {
      if (!shopDomain) {
        console.log("[checkThemeIntegration] No shop domain, returning false");
        return false;
      }

      const response = await fetch(
        `https://${process.env.APP_HOST}/order_confirmations/is_cod_king_block_enabled?shopifyDomain=${shopDomain}`,
      );
      const data = await response.json();
      const enabled = data.assetEnabled === true;
      console.log(
        "[checkThemeIntegration] API response:",
        data,
        "| enabled:",
        enabled,
      );
      setIsExtensionEnabled(enabled);
      return enabled;
    } catch (error) {
      console.error("Error checking theme integration:", error);
      setIsExtensionEnabled(false);
      return false;
    }
  }, [shopDomain]);

  // Manual refresh function for theme integration status
  const handleRefreshThemeStatus = useCallback(async () => {
    journeyTracker.trackButtonClick("check_theme_status", {
      step: 3,
      feature: "quick-onboarding-v2",
    });
    setIsRefreshingTheme(true);
    try {
      await checkThemeIntegration();
    } finally {
      setIsRefreshingTheme(false);
    }
  }, [checkThemeIntegration, journeyTracker]);

  // Start monitoring theme integration after user clicks the theme button
  const startThemeMonitoring = useCallback(() => {
    setIsCheckingTheme(true);
    setThemeCheckTimedOut(false);
    checkCountRef.current = 0;
    const interval = setInterval(async () => {
      checkCountRef.current += 1;
      const isEnabled = await checkThemeIntegration();
      console.log(
        `[Theme Check #${checkCountRef.current}] Extension enabled:`,
        isEnabled,
      );
      if (isEnabled || checkCountRef.current >= 24) {
        clearInterval(interval);
        setThemeCheckInterval(null);
        setIsCheckingTheme(false);
        // Only auto-advance to step 4 if extension is TRULY enabled
        if (isEnabled === true) {
          console.log(
            "[Theme Check] Extension confirmed enabled, advancing to step 4",
          );
          journeyTracker.trackEvent("theme_embed_detected", { step: 3 });
          // With the COD Form picked too, stay here until its own embed is on.
          // (With the COD Form picked, "enabled" here may be the other embed: the merchant
          // continues with the button once both show as on.)
          if (!codFormOnRef.current) setCurrentStep(4);
        } else {
          // Polled out without finding it — surface help + a way forward.
          setThemeCheckTimedOut(true);
        }
      }
    }, 3000);
    setThemeCheckInterval(interval);
  }, [checkThemeIntegration, journeyTracker]);

  // Let the merchant proceed even if the embed isn't detected, so a flaky/external
  // check never traps them. They're nudged to finish it from the dashboard afterwards.
  const handleSkipThemeStep = useCallback(() => {
    journeyTracker.trackEvent("theme_embed_skipped", { step: 3 });
    journeyTracker.trackButtonClick("skip_theme_extension", {
      step: 3,
      feature: "quick-onboarding-v2",
    });
    setCurrentStep(4);
  }, [journeyTracker]);

  // Handle theme integration button click
  const handleThemeIntegrationClick = useCallback(() => {
    if (!shopDomain) {
      console.error("Shop domain not available");
      return;
    }
    journeyTracker.trackButtonClick("open_theme_editor", {
      step: 3,
      feature: "quick-onboarding-v2",
    });
    startThemeMonitoring();
    window.open(
      `https://${shopDomain}/admin/themes/current/editor?context=apps&template=cart&activateAppId=99553eb5-bf07-4ce0-9263-7e5f10cab22c/app-embed`,
      "_blank",
    );
  }, [shopDomain, startThemeMonitoring, journeyTracker]);

  // Check theme status on step 3 mount
  useEffect(() => {
    if (currentStep === 3) {
      checkThemeIntegration();
    }
  }, [currentStep, checkThemeIntegration]);

  // The older embed serves OTP / partial payment; the COD Form has an app embed of its own.
  const requiresLegacyExtension =
    otpVerificationEnabled || partialPaymentEnabled;
  const requiresCheckoutExtension = requiresLegacyExtension || codFormOn;
  const legacyEmbedOn = codFormOn && legacyEmbedExact !== null ? legacyEmbedExact : isExtensionEnabled;

  // Theme embed is only needed for checkout (OTP / partial payment), not engagement-only
  useEffect(() => {
    if (currentStep === 3 && codFormLoaded && !requiresCheckoutExtension) {
      setCurrentStep(4);
    }
  }, [currentStep, requiresCheckoutExtension, codFormLoaded]);

  // Cleanup interval on unmount
  useEffect(() => {
    return () => {
      if (themeCheckInterval) {
        clearInterval(themeCheckInterval);
      }
    };
  }, [themeCheckInterval]);

  // Initial loading - wait for shop data; when returning from billing (restored step > 1), show content immediately
  useEffect(() => {
    const hasShop =
      shop?.shopify_domain || window.shopOrigin || window.Shopify?.shop;
    if (currentStep > 1) {
      setIsLoading(false);
      return;
    }
    if (hasShop) {
      setIsLoading(false);
    } else {
      const timer = setTimeout(() => setIsLoading(false), 800);
      return () => clearTimeout(timer);
    }
  }, [shop, currentStep]);

  // Safety: never stay in loading forever (e.g. if shop never resolves when returning from billing)
  useEffect(() => {
    const timer = setTimeout(() => setIsLoading(false), 1500);
    return () => clearTimeout(timer);
  }, []);

  const truthySetting = useCallback((v) => {
    if (v === true || v === "true" || v === 1 || v === "1") return true;
    return false;
  }, []);

  // Sync OTP, partial payment, and engagement toggles from setting when page loads
  useEffect(() => {
    if (!setting || typeof setting !== "object") return;
    const preOrderOtp =
      setting.enablePreOrderOtp ?? setting.enable_pre_order_otp;
    const partialPayment =
      setting.partialPaymentEnabled ?? setting.partial_payment_enabled;
    setOtpVerificationEnabled(Boolean(preOrderOtp));
    setPartialPaymentEnabled(Boolean(partialPayment));
    setSmsConfirmation(
      truthySetting(
        setting.confirmationSmsEnabled ?? setting.confirmation_sms_enabled,
      ),
    );
    setSmsFulfilment(
      truthySetting(
        setting.enableFulfilmentMessage ?? setting.enable_fulfilment_message,
      ),
    );
    setSmsAbandoned(
      truthySetting(
        setting.abandonedCartEnabled ?? setting.abandoned_cart_enabled,
      ),
    );
    setWaConfirmation(
      truthySetting(
        setting.confirmationWhatsapp ?? setting.confirmation_whatsapp,
      ),
    );
    setWaFulfilment(
      truthySetting(setting.fulfilmentWhatsapp ?? setting.fulfilment_whatsapp),
    );
    setWaAbandoned(truthySetting(setting.acWhatsapp ?? setting.ac_whatsapp));
    setWaCodVerification(
      truthySetting(
        setting.sendVerificationLinkOnly ?? setting.send_verification_link_only,
      ),
    );
  }, [setting?.id, truthySetting]);

  // Track page load once when wizard is ready (avoid one POST per step)
  const hasTrackedPageLoadRef = useRef(false);
  const onboardingStartedAtRef = useRef(null);
  const stepViewedAtRef = useRef(null);

  useEffect(() => {
    if (isLoading || hasTrackedPageLoadRef.current) return;
    hasTrackedPageLoadRef.current = true;
    onboardingStartedAtRef.current = Date.now();
    stepViewedAtRef.current = Date.now();
    journeyTracker.trackPageLoad({
      step: 1,
      feature: "quick-onboarding-v2",
    });
    // Funnel stage 1: top of the onboarding funnel (append-only).
    journeyTracker.trackEvent("onboarding_started", { step: 1 });
  }, [isLoading]);

  // Record step view time when step changes (for duration calculation when they leave)
  useEffect(() => {
    stepViewedAtRef.current = Date.now();
  }, [currentStep]);

  // Persist step-2 feature toggles (OTP, partial payment, engagement) when changed on step 2
  const saveStep2Settings = useCallback(
    (patch = {}) => {
      const merged = {
        otpVerificationEnabled,
        partialPaymentEnabled,
        smsConfirmation,
        smsFulfilment,
        smsAbandoned,
        waConfirmation,
        waFulfilment,
        waAbandoned,
        waCodVerification,
        ...patch,
      };
      const updatedSetting = {
        ...setting,
        enablePreOrderOtp: merged.otpVerificationEnabled === true ? "true" : "false",
        partialPaymentEnabled: Boolean(merged.partialPaymentEnabled),
        confirmationSmsEnabled: Boolean(merged.smsConfirmation),
        enableFulfilmentMessage: Boolean(merged.smsFulfilment),
        abandonedCartEnabled: Boolean(merged.smsAbandoned),
        confirmationWhatsapp: Boolean(merged.waConfirmation),
        fulfilmentWhatsapp: Boolean(merged.waFulfilment),
        acWhatsapp: Boolean(merged.waAbandoned),
        sendVerificationLinkOnly: Boolean(merged.waCodVerification),
      };
      Api.post("/settings", { setting: updatedSetting })
        .then((response) => {
          setSetting(response.data);
        })
        .catch((err) => {
          console.error("Error saving feature toggles:", err);
        });
    },
    [
      setting,
      setSetting,
      otpVerificationEnabled,
      partialPaymentEnabled,
      smsConfirmation,
      smsFulfilment,
      smsAbandoned,
      waConfirmation,
      waFulfilment,
      waAbandoned,
      waCodVerification,
    ],
  );

  const handleOtpChange = useCallback(
    (checked) => {
      setOtpVerificationEnabled(checked);
      if (currentStep === 2) {
        saveStep2Settings({ otpVerificationEnabled: checked });
      }
    },
    [currentStep, saveStep2Settings],
  );

  const handlePartialPaymentChange = useCallback(
    (checked) => {
      setPartialPaymentEnabled(checked);
      if (currentStep === 2) {
        saveStep2Settings({ partialPaymentEnabled: checked });
      }
    },
    [currentStep, saveStep2Settings],
  );

  const handleSmsParentChange = useCallback(
    (checked) => {
      setSmsConfirmation(checked);
      setSmsFulfilment(checked);
      setSmsAbandoned(checked);
      if (currentStep === 2) {
        saveStep2Settings({
          smsConfirmation: checked,
          smsFulfilment: checked,
          smsAbandoned: checked,
        });
      }
    },
    [currentStep, saveStep2Settings],
  );

  const handleWaParentChange = useCallback(
    (checked) => {
      setWaConfirmation(checked);
      setWaFulfilment(checked);
      setWaAbandoned(checked);
      setWaCodVerification(checked);
      if (currentStep === 2) {
        saveStep2Settings({
          waConfirmation: checked,
          waFulfilment: checked,
          waAbandoned: checked,
          waCodVerification: checked,
        });
      }
    },
    [currentStep, saveStep2Settings],
  );

  const handleSmsConfirmationChange = useCallback(
    (checked) => {
      setSmsConfirmation(checked);
      if (currentStep === 2) saveStep2Settings({ smsConfirmation: checked });
    },
    [currentStep, saveStep2Settings],
  );

  const handleSmsFulfilmentChange = useCallback(
    (checked) => {
      setSmsFulfilment(checked);
      if (currentStep === 2) saveStep2Settings({ smsFulfilment: checked });
    },
    [currentStep, saveStep2Settings],
  );

  const handleSmsAbandonedChange = useCallback(
    (checked) => {
      setSmsAbandoned(checked);
      if (currentStep === 2) saveStep2Settings({ smsAbandoned: checked });
    },
    [currentStep, saveStep2Settings],
  );

  const handleWaConfirmationChange = useCallback(
    (checked) => {
      setWaConfirmation(checked);
      if (currentStep === 2) saveStep2Settings({ waConfirmation: checked });
    },
    [currentStep, saveStep2Settings],
  );

  const handleWaFulfilmentChange = useCallback(
    (checked) => {
      setWaFulfilment(checked);
      if (currentStep === 2) saveStep2Settings({ waFulfilment: checked });
    },
    [currentStep, saveStep2Settings],
  );

  const handleWaAbandonedChange = useCallback(
    (checked) => {
      setWaAbandoned(checked);
      if (currentStep === 2) saveStep2Settings({ waAbandoned: checked });
    },
    [currentStep, saveStep2Settings],
  );

  const handleWaCodVerificationChange = useCallback(
    (checked) => {
      setWaCodVerification(checked);
      if (currentStep === 2) saveStep2Settings({ waCodVerification: checked });
    },
    [currentStep, saveStep2Settings],
  );

  const goToNextStep = useCallback(() => {
    setCurrentStep((prev) => Math.min(prev + 1, 4));
  }, []);

  const getTimeSpentContext = useCallback(() => {
    const now = Date.now();
    const stepViewedAt = stepViewedAtRef.current || now;
    const startedAt = onboardingStartedAtRef.current || now;
    return {
      durationSeconds: Math.round((now - stepViewedAt) / 1000),
      totalTimeSeconds: Math.round((now - startedAt) / 1000),
    };
  }, []);

  const handleStartSetup = useCallback(() => {
    journeyTracker.trackButtonClick("start_setup", {
      step: 1,
      feature: "quick-onboarding-v2",
      ...getTimeSpentContext(),
    });
    journeyTracker.trackTimeSpent({ step: 1, ...getTimeSpentContext() });
    goToNextStep();
  }, [journeyTracker, goToNextStep, getTimeSpentContext]);

  const handleStep3Continue = useCallback(() => {
    journeyTracker.trackButtonClick("continue", {
      step: 3,
      feature: "quick-onboarding-v2",
      extensionEnabled: true,
      ...getTimeSpentContext(),
    });
    journeyTracker.trackTimeSpent({ step: 3, ...getTimeSpentContext() });
    goToNextStep();
  }, [journeyTracker, goToNextStep, getTimeSpentContext]);

  // When Continue is clicked on step 2: extension step only if OTP or partial payment is on
  const handleStep2Continue = useCallback(() => {
    const needExtension = otpVerificationEnabled || partialPaymentEnabled || codFormOn;
    journeyTracker.trackButtonClick("continue", {
      step: 2,
      feature: "quick-onboarding-v2",
      otpVerificationEnabled,
      partialPaymentEnabled,
      skippedExtensionStep: !needExtension,
      ...getTimeSpentContext(),
    });
    journeyTracker.trackTimeSpent({ step: 2, ...getTimeSpentContext() });
    // Funnel stage 2: merchant picked at least one feature and advanced.
    journeyTracker.trackEvent("features_selected", {
      step: 2,
      otpVerificationEnabled,
      partialPaymentEnabled,
      smsConfirmation,
      smsFulfilment,
      smsAbandoned,
      waConfirmation,
      waFulfilment,
      waAbandoned,
      waCodVerification,
      skippedExtensionStep: !needExtension,
    });
    setCurrentStep(needExtension ? 3 : 4);

    // Always send explicit booleans so backend reliably disables pre-order OTP when unchecked.
    // Backend coerces via .to_s.downcase == "true"; sending string "false" ensures disable is applied.
    // (Journey is recorded via trackEvent above — never stamp it onto the settings save.)
    const updatedSetting = {
      ...setting,
      partialPaymentEnabled: Boolean(partialPaymentEnabled),
      enablePreOrderOtp: otpVerificationEnabled === true ? "true" : "false",
      confirmationSmsEnabled: Boolean(smsConfirmation),
      enableFulfilmentMessage: Boolean(smsFulfilment),
      abandonedCartEnabled: Boolean(smsAbandoned),
      confirmationWhatsapp: Boolean(waConfirmation),
      fulfilmentWhatsapp: Boolean(waFulfilment),
      acWhatsapp: Boolean(waAbandoned),
      sendVerificationLinkOnly: Boolean(waCodVerification),
    };
    Api.post("/settings", { setting: updatedSetting })
      .then((response) => {
        setSetting(response.data);
      })
      .catch((error) => {
        console.error("Error saving onboarding settings:", error);
        journeyTracker.trackError("save_settings_error", error.message, {
          step: 2,
          feature: "quick-onboarding-v2",
        });
      });
  }, [
    setting,
    partialPaymentEnabled,
    otpVerificationEnabled,
    smsConfirmation,
    smsFulfilment,
    smsAbandoned,
    waConfirmation,
    waFulfilment,
    waAbandoned,
    waCodVerification,
    setSetting,
    journeyTracker,
    getTimeSpentContext,
    codFormOn,
  ]);

  const goToPreviousStep = useCallback(() => {
    journeyTracker.trackButtonClick("back", {
      step: currentStep,
      fromStep: currentStep,
      toStep: currentStep - 1,
      feature: "quick-onboarding-v2",
      ...getTimeSpentContext(),
    });
    journeyTracker.trackTimeSpent({
      step: currentStep,
      ...getTimeSpentContext(),
    });
    setCurrentStep((prev) => {
      if (prev === 4) {
        const needExt = otpVerificationEnabled || partialPaymentEnabled || codFormOn;
        return needExt ? 3 : 2;
      }
      return Math.max(prev - 1, 1);
    });
  }, [
    currentStep,
    otpVerificationEnabled,
    partialPaymentEnabled,
    codFormOn,
    journeyTracker,
    getTimeSpentContext,
  ]);

  const handleStep4Back = useCallback(() => {
    const needExt = otpVerificationEnabled || partialPaymentEnabled || codFormOn;
    journeyTracker.trackButtonClick("back", {
      step: 4,
      fromStep: 4,
      toStep: needExt ? 3 : 2,
      feature: "quick-onboarding-v2",
      ...getTimeSpentContext(),
    });
    journeyTracker.trackTimeSpent({
      step: 4,
      ...getTimeSpentContext(),
    });
    setCurrentStep(needExt ? 3 : 2);
  }, [otpVerificationEnabled, partialPaymentEnabled, codFormOn, journeyTracker, getTimeSpentContext]);

  const handleEnableBilling = useCallback(
    (e) => {
      const timeContext = getTimeSpentContext();
      journeyTracker.trackButtonClick("enable_billing", {
        step: 4,
        feature: "quick-onboarding-v2",
        ...timeContext,
      });
      journeyTracker.trackTimeSpent({
        step: 4,
        action: "completed",
        ...timeContext,
      });
      // Funnel stage 4: merchant chose to activate a plan and entered billing.
      journeyTracker.trackEvent("billing_started", { step: 4 });
      markCustomSetupPendingAfterBilling();
      handleRedirect(e, "/quick-onboarding/billing");
    },
    [handleRedirect, journeyTracker, getTimeSpentContext],
  );

  const handleGoToDashboard = useCallback(
    (e) => {
      // Merchant skipped billing and went straight to the dashboard (non-funnel context event).
      journeyTracker.trackEvent("reached_dashboard", { step: 4 });
      handleRedirect(e, "/");
    },
    [handleRedirect, journeyTracker],
  );

  // Prefill the test phone from the shop owner's number.
  useEffect(() => {
    const current = shop?.ownerPhone ?? shop?.owner_phone ?? "";
    setTestPhone(String(current || ""));
  }, [shop?.ownerPhone, shop?.owner_phone]);

  // Send a real notification to the merchant's own phone before billing (the aha moment).
  // Persists the entered phone first (test_notification sends to shop.owner_phone), then fires
  // the 'test_sent' funnel event on success.
  const sendOnboardingTest = useCallback(
    async (mode) => {
      if (!shop?.id) return;
      const phone = testPhone.trim();
      if (!phone) {
        setTestBanner({
          tone: "critical",
          title: I18n.t("quick_onboarding_v2.test_phone_required"),
        });
        return;
      }

      // Test messages use sample values and send regardless of the (legacy) approval
      // flag — that flag only gates live customer delivery, not these test sends.
      setTestLoadingMode(mode);
      setTestBanner(null);

      // The auth redirect (expired embedded session) returns HTML, not JSON.
      const looksLikeAuthRedirect = (res) =>
        typeof res?.data === "string" ||
        /\/login|sessions/i.test(res?.request?.responseURL || "");
      const showSessionExpired = () =>
        setTestBanner({
          tone: "warning",
          title: I18n.t("quick_onboarding_v2.test_session_expired_title"),
          message: I18n.t("quick_onboarding_v2.test_session_expired"),
        });

      try {
        const storedPhone = String(
          shop?.ownerPhone ?? shop?.owner_phone ?? "",
        ).trim();
        if (phone !== storedPhone) {
          const saveRes = await Api.post("/settings/update_owner_phone", {
            shop_id: shop.id,
            owner_phone: phone,
          });
          if (looksLikeAuthRedirect(saveRes)) {
            showSessionExpired();
            return;
          }
          if (saveRes.data?.success) {
            const stored = saveRes.data.ownerPhone ?? saveRes.data.owner_phone;
            setShop((prev) =>
              prev ? { ...prev, owner_phone: stored, ownerPhone: stored } : prev,
            );
          }
        }
        // Test the message that's actually enabled for this channel — otherwise a
        // shop that only turned on (say) WhatsApp COD verification would receive a
        // generic order-placed test instead. First enabled in priority order wins.
        const priority =
          mode === "whatsapp"
            ? [
                [waConfirmation, "order_confirmation"],
                [waFulfilment, "order_fulfilment"],
                [waCodVerification, "cod_verification"],
              ]
            : [
                [smsConfirmation, "order_confirmation"],
                [smsFulfilment, "order_fulfilment"],
              ];
        const testType = (priority.find(([on]) => on) || [
          true,
          "order_confirmation",
        ])[1];

        const res = await Api.post("/settings/test_notification", {
          type: testType,
          mode,
          shop_id: shop.id,
        });
        if (looksLikeAuthRedirect(res)) {
          showSessionExpired();
          return;
        }
        if (res.data?.success) {
          const sentTo = res.data.number || phone;
          setTestBanner({
            tone: "success",
            title:
              mode === "sms"
                ? I18n.t("admin.test_sms_success")
                : I18n.t("admin.test_whatsapp_success"),
            message: I18n.t("quick_onboarding_v2.test_sent_body", {
              number: sentTo,
            }),
          });
          journeyTracker.trackEvent("test_sent", {
            step: 4,
            mode,
            type: testType,
          });
        } else {
          throw new Error("Test failed");
        }
      } catch (error) {
        const status = error?.response?.status;
        if (status === 401 || status === 403 || status === 302) {
          showSessionExpired();
          return;
        }
        const errText =
          error.response?.data?.error || I18n.t("admin.something_went_wrong");
        setTestBanner({
          tone: "critical",
          title:
            mode === "sms"
              ? I18n.t("admin.test_sms_failed")
              : I18n.t("admin.test_whatsapp_failed"),
          message:
            typeof errText === "string"
              ? errText
              : I18n.t("admin.something_went_wrong"),
        });
      } finally {
        setTestLoadingMode(null);
      }
    },
    [
      shop,
      setShop,
      testPhone,
      journeyTracker,
      waConfirmation,
      waFulfilment,
      waCodVerification,
      smsConfirmation,
      smsFulfilment,
    ],
  );

  const hasAnyEngagement =
    smsConfirmation ||
    smsFulfilment ||
    smsAbandoned ||
    waConfirmation ||
    waFulfilment ||
    waAbandoned ||
    waCodVerification;

  const isStep2Valid =
    otpVerificationEnabled || partialPaymentEnabled || hasAnyEngagement || codFormOn;

  const smsParentChecked =
    smsConfirmation && smsFulfilment && smsAbandoned;
  const smsParentIndeterminate =
    !smsParentChecked &&
    (smsConfirmation || smsFulfilment || smsAbandoned);
  const waParentChecked =
    waConfirmation && waFulfilment && waAbandoned && waCodVerification;
  const waParentIndeterminate =
    !waParentChecked &&
    (waConfirmation || waFulfilment || waAbandoned || waCodVerification);

  const renderStep1 = () => (
    <Card>
      <BlockStack gap="500">
        <InlineStack align="space-between" blockAlign="center">
          <InlineStack gap="200" blockAlign="center">
            <Text variant="headingLg" as="h1">
              {I18n.t("quick_onboarding_v2.welcome_to")}
            </Text>
            <img
              src="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/with_bg_logo2.png?v=1757062726"
              alt={I18n.t("quick_onboarding_v2.cod_king")}
              style={{ height: "32px", objectFit: "contain" }}
            />
          </InlineStack>
          <Box minWidth="150px">
            <LanguageDropdown silentSave />
          </Box>
        </InlineStack>

        <Text variant="bodyMd" as="p" tone="subdued">
          {I18n.t("quick_onboarding_v2.step1_subtitle")}
        </Text>

        <Box paddingBlockStart="400">
          <InlineStack align="end">
            <Button variant="primary" onClick={handleStartSetup}>
              {I18n.t("quick_onboarding_v2.get_started")}
            </Button>
          </InlineStack>
        </Box>
      </BlockStack>
    </Card>
  );

  const handleOtherFeatures = useCallback(
    (e) => {
      if (e) e.preventDefault();
      handleRedirect(e, "/quick-onboarding/all-features");
    },
    [handleRedirect],
  );

  const renderStep2 = () => {
    const advancedTools = [
      {
        labelKey: "smart_cod_restrictions",
        path: "/quick-onboarding/limit-cod",
      },
      {
        labelKey: "whatsapp_sms_updates",
        path: "/quick-onboarding/notifications",
      },
      {
        labelKey: "cart_recovery_reminders",
        path: "/quick-onboarding/notifications",
      },
      { labelKey: "cod_fees", path: "/quick-onboarding/fees" },
      // {
      //   label: "COD to Prepaid Incentives",
      //   path: "/features/cod-to-prepaid",
      // },
    ];

    const previewSetting = {
      ...setting,
      enablePreOrderOtp: otpVerificationEnabled,
      partialPaymentEnabled,
    };

    return (
      <InlineGrid columns={{ xs: 1, lg: "minmax(0, 3fr) minmax(0, 2fr)" }} gap="400">
        <Card>
          <BlockStack gap="500">
            <Text variant="headingLg" as="h1">
              {I18n.t("quick_onboarding_v2.step2_title")}
            </Text>

            <Text variant="bodyMd" as="p" tone="subdued">
              {I18n.t("quick_onboarding_v2.step2_subtitle")}
            </Text>
            <BlockStack gap="400">
              <Box
                padding="400"
                background="bg-surface-secondary"
                borderRadius="200"
              >
                <BlockStack gap="200">
                  <FeatureCheckbox
                    tooltip={I18n.t(
                      "quick_onboarding_v2.phone_verification_otp_desc",
                    )}
                    label={I18n.t("quick_onboarding_v2.phone_verification_otp")}
                    checked={otpVerificationEnabled}
                    onChange={handleOtpChange}
                  />
                  <Box paddingInlineStart="600">
                    <Text variant="bodySm" as="p" tone="subdued">
                      {I18n.t("quick_onboarding_v2.phone_verification_otp_desc")}
                    </Text>
                  </Box>
                </BlockStack>
              </Box>

              <Box
                padding="400"
                background="bg-surface-secondary"
                borderRadius="200"
              >
                <BlockStack gap="200">
                  <FeatureCheckbox
                    tooltip={I18n.t("quick_onboarding_v2.partial_payment_desc")}
                    label={I18n.t("quick_onboarding_v2.partial_payment")}
                    checked={partialPaymentEnabled}
                    onChange={handlePartialPaymentChange}
                  />
                  <Box paddingInlineStart="600">
                    <Text variant="bodySm" as="p" tone="subdued">
                      {I18n.t("quick_onboarding_v2.partial_payment_desc")}
                    </Text>
                  </Box>
                </BlockStack>
              </Box>

              {/* COD Form as a feature (only for stores that have the module) */}
              <OnboardingSetupStep />

              <Box
                padding="400"
                background="bg-surface-secondary"
                borderRadius="200"
              >
                <BlockStack gap="400">
                  <BlockStack gap="100">
                    <Text variant="headingSm" as="h2">
                      {I18n.t("quick_onboarding_v2.engagement_title")}
                    </Text>
                    <Text variant="bodySm" as="p" tone="subdued">
                      {I18n.t("quick_onboarding_v2.engagement_subtitle")}
                    </Text>
                    <Text variant="bodySm" as="p" tone="subdued">
                      {I18n.t("quick_onboarding_v2.engagement_templates_paid")}
                    </Text>
                  </BlockStack>
                  <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                    <BlockStack gap="200">
                      <FeatureCheckbox
                        tooltip={I18n.t("quick_onboarding_v2.sms_updates_desc")}
                        label={I18n.t("quick_onboarding_v2.sms_updates")}
                        checked={smsParentChecked}
                        indeterminate={smsParentIndeterminate}
                        onChange={handleSmsParentChange}
                      />
                      <Box paddingInlineStart="600">
                        <BlockStack gap="100">
                          <FeatureCheckbox
                            tooltip={I18n.t(
                              "quick_onboarding_v2.notif_fulfillment_desc",
                            )}
                            label={I18n.t("quick_onboarding_v2.notif_fulfillment")}
                            checked={smsFulfilment}
                            onChange={handleSmsFulfilmentChange}
                          />
                          <FeatureCheckbox
                            tooltip={I18n.t(
                              "quick_onboarding_v2.notif_confirmation_desc",
                            )}
                            label={I18n.t(
                              "quick_onboarding_v2.notif_confirmation",
                            )}
                            checked={smsConfirmation}
                            onChange={handleSmsConfirmationChange}
                          />
                          <FeatureCheckbox
                            tooltip={I18n.t(
                              "quick_onboarding_v2.notif_abandoned_cart_desc",
                            )}
                            label={I18n.t(
                              "quick_onboarding_v2.notif_abandoned_cart",
                            )}
                            checked={smsAbandoned}
                            onChange={handleSmsAbandonedChange}
                          />
                        </BlockStack>
                      </Box>
                    </BlockStack>
                    <BlockStack gap="200">
                      <FeatureCheckbox
                        tooltip={I18n.t(
                          "quick_onboarding_v2.whatsapp_updates_desc",
                        )}
                        label={I18n.t("quick_onboarding_v2.whatsapp_updates")}
                        checked={waParentChecked}
                        indeterminate={waParentIndeterminate}
                        onChange={handleWaParentChange}
                      />
                      <Box paddingInlineStart="600">
                        <BlockStack gap="100">
                          <FeatureCheckbox
                            tooltip={I18n.t(
                              "quick_onboarding_v2.notif_fulfillment_desc",
                            )}
                            label={I18n.t("quick_onboarding_v2.notif_fulfillment")}
                            checked={waFulfilment}
                            onChange={handleWaFulfilmentChange}
                          />
                          <FeatureCheckbox
                            tooltip={I18n.t(
                              "quick_onboarding_v2.notif_confirmation_desc",
                            )}
                            label={I18n.t(
                              "quick_onboarding_v2.notif_confirmation",
                            )}
                            checked={waConfirmation}
                            onChange={handleWaConfirmationChange}
                          />
                          <FeatureCheckbox
                            tooltip={I18n.t(
                              "quick_onboarding_v2.notif_abandoned_cart_desc",
                            )}
                            label={I18n.t(
                              "quick_onboarding_v2.notif_abandoned_cart",
                            )}
                            checked={waAbandoned}
                            onChange={handleWaAbandonedChange}
                          />
                          <FeatureCheckbox
                            tooltip={I18n.t(
                              "quick_onboarding_v2.notif_cod_verification_desc",
                            )}
                            label={I18n.t(
                              "quick_onboarding_v2.notif_cod_verification",
                            )}
                            checked={waCodVerification}
                            onChange={handleWaCodVerificationChange}
                          />
                        </BlockStack>
                      </Box>
                    </BlockStack>
                  </InlineGrid>
                  <Text variant="bodySm" as="p" tone="subdued">
                    {I18n.t("quick_onboarding_v2.engagement_test_hint")}
                  </Text>
                </BlockStack>
              </Box>
            </BlockStack>

            <Divider />

            <BlockStack gap="300">
              <Button
                variant="plain"
                onClick={() => setAdvancedOpen(!advancedOpen)}
                ariaControls="advanced-tools-collapsible"
                ariaExpanded={advancedOpen}
              >
                {I18n.t("quick_onboarding_v2.view_advanced_tools")}
              </Button>
              <Collapsible open={advancedOpen} id="advanced-tools-collapsible">
                <BlockStack gap="200">
                  {advancedTools.map(({ labelKey, path }) => (
                    <Link
                      key={path + labelKey}
                      url="#"
                      onClick={(e) => {
                        e.preventDefault();
                        handleRedirect(e, path);
                      }}
                    >
                      {I18n.t(`quick_onboarding_v2.${labelKey}`)}
                    </Link>
                  ))}
                </BlockStack>
              </Collapsible>
            </BlockStack>

            <Box paddingBlockStart="400">
              <InlineStack align="space-between">
                <Button onClick={goToPreviousStep}>
                  {I18n.t("quick_onboarding_v2.back")}
                </Button>
                <Button
                  variant="primary"
                  onClick={handleStep2Continue}
                  disabled={!isStep2Valid}
                >
                  {I18n.t("quick_onboarding_v2.continue")}
                </Button>
              </InlineStack>
            </Box>
          </BlockStack>
        </Card>
        <div style={{ position: "sticky", top: 16, alignSelf: "start" }}>
          <BlockStack gap="200">
            <BlockStack gap="050">
              <Text variant="headingSm" as="h2">
                {I18n.t("checkout_form_preview.onboarding_title")}
              </Text>
              <Text variant="bodySm" as="p" tone="subdued">
                {I18n.t("checkout_form_preview.onboarding_help")}
              </Text>
            </BlockStack>
            {/* With only the COD Form picked, its preview takes the place of the "nothing enabled" note */}
            {(otpVerificationEnabled || partialPaymentEnabled || !codFormOn) && (
              <WidgetPreviewPanel setting={previewSetting} />
            )}
            <OnboardingFormPreview />
          </BlockStack>
        </div>
      </InlineGrid>
    );
  };

  const renderStep3 = () => (
    <Card>
      <BlockStack gap="600">
        {/* Header */}
        <BlockStack gap="200">
          <Text variant="headingLg" as="h1">
            {I18n.t("quick_onboarding_v2.step3_title")}
          </Text>
          <Text variant="bodyMd" as="p" tone="subdued">
            {I18n.t("quick_onboarding_v2.step3_subtitle")}
          </Text>
        </BlockStack>

        {codFormOn && <OnboardingEmbedStep onStatus={onCodFormEmbedStatus} />}

        {/* Status Section */}
        {!requiresLegacyExtension ? null : legacyEmbedOn ? (
          <Box padding="500" background="bg-surface-success" borderRadius="300">
            <BlockStack gap="400" inlineAlign="center">
              <Box
                padding="300"
                background="bg-fill-success"
                borderRadius="full"
              >
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    width: "32px",
                    height: "32px",
                  }}
                >
                  <svg
                    width="24"
                    height="24"
                    viewBox="0 0 20 20"
                    fill="#ffffff"
                  >
                    <path
                      fillRule="evenodd"
                      d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                      clipRule="evenodd"
                    />
                  </svg>
                </div>
              </Box>
              <BlockStack gap="100" inlineAlign="center">
                <Text variant="headingMd" as="h3">
                  {I18n.t("quick_onboarding_v2.extension_activated")}
                </Text>
                <Text variant="bodyMd" tone="subdued">
                  {I18n.t("quick_onboarding_v2.extension_activated_desc")}
                </Text>
              </BlockStack>
            </BlockStack>
          </Box>
        ) : (
          <BlockStack gap="400">
            {/* Action Card */}
            <Box
              padding="500"
              borderWidth="025"
              borderColor="border"
              borderRadius="300"
            >
              <BlockStack gap="400">
                <InlineStack align="space-between" blockAlign="start">
                  <BlockStack gap="200">
                    <InlineStack gap="200" blockAlign="center">
                      <Text variant="headingMd" as="h3">
                        {I18n.t("quick_onboarding_v2.theme_integration")}
                      </Text>
                      <Badge tone="attention">
                        {I18n.t("quick_onboarding_v2.required")}
                      </Badge>
                    </InlineStack>
                    <Text variant="bodyMd" tone="subdued">
                      {I18n.t("quick_onboarding_v2.theme_integration_desc")}
                    </Text>
                  </BlockStack>
                  {(isCheckingTheme || isRefreshingTheme) && (
                    <Spinner size="small" />
                  )}
                </InlineStack>

                <InlineStack gap="300">
                  <Button
                    variant="primary"
                    size="large"
                    icon={ExternalMinor}
                    onClick={handleThemeIntegrationClick}
                    loading={isCheckingTheme}
                  >
                    {I18n.t("quick_onboarding_v2.open_theme_editor")}
                  </Button>
                  <Button
                    variant="tertiary"
                    icon={RefreshMinor}
                    onClick={handleRefreshThemeStatus}
                    loading={isRefreshingTheme}
                  >
                    {I18n.t("quick_onboarding_v2.check_status")}
                  </Button>
                </InlineStack>
              </BlockStack>
            </Box>

            {/* Animated walkthrough: the embed switch, then a zoom on Save */}
            <AppEmbedTutorial buttonLabel={I18n.t("quick_onboarding_v2.open_theme_editor")} />

            {/* Status indicator while monitoring */}
            {isCheckingTheme && (
              <Banner tone="info">
                <InlineStack gap="200" blockAlign="center">
                  <Spinner size="small" />
                  <Text variant="bodyMd">
                    {I18n.t("quick_onboarding_v2.waiting_extension")}
                  </Text>
                </InlineStack>
              </Banner>
            )}

            {/* Couldn't auto-detect — reassure and offer a way forward (not a dead-end). */}
            {themeCheckTimedOut && !isCheckingTheme && (
              <Banner tone="warning">
                <BlockStack gap="200">
                  <Text variant="bodyMd">
                    {I18n.t("quick_onboarding_v2.theme_not_detected")}
                  </Text>
                  <InlineStack gap="300">
                    <Button onClick={handleRefreshThemeStatus} loading={isRefreshingTheme}>
                      {I18n.t("quick_onboarding_v2.check_status")}
                    </Button>
                    <Button variant="plain" onClick={handleSkipThemeStep}>
                      {I18n.t("quick_onboarding_v2.skip_for_now")}
                    </Button>
                  </InlineStack>
                </BlockStack>
              </Banner>
            )}
          </BlockStack>
        )}

        {/* Footer Actions */}
        <Box paddingBlockStart="200">
          <InlineStack align="space-between">
            <Button onClick={goToPreviousStep}>
              {I18n.t("quick_onboarding_v2.back")}
            </Button>
            {(!requiresLegacyExtension || legacyEmbedOn) &&
            (!codFormOn || codFormEmbedOn) ? (
              <Button variant="primary" onClick={handleStep3Continue}>
                {I18n.t("quick_onboarding_v2.continue")}
              </Button>
            ) : (
              // Escape hatch: never trap the merchant behind a flaky external check.
              <Button onClick={handleSkipThemeStep}>
                {I18n.t("quick_onboarding_v2.skip_for_now")}
              </Button>
            )}
          </InlineStack>
        </Box>
      </BlockStack>
    </Card>
  );

  const renderStep4 = () => {
    const enabledFeatures = [];

    if (otpVerificationEnabled) {
      enabledFeatures.push(
        I18n.t("quick_onboarding_v2.phone_verification_otp"),
      );
    }

    if (partialPaymentEnabled) {
      enabledFeatures.push(I18n.t("quick_onboarding_v2.partial_payment"));
    }

    if (codFormOn) {
      enabledFeatures.push(
        I18n.t("cod_form.onboarding.title", { defaultValue: "COD Form" }),
      );
    }

    if (smsConfirmation) {
      enabledFeatures.push(I18n.t("quick_onboarding_v2.feature_sms_confirmation"));
    }
    if (smsFulfilment) {
      enabledFeatures.push(I18n.t("quick_onboarding_v2.feature_sms_fulfillment"));
    }
    if (smsAbandoned) {
      enabledFeatures.push(I18n.t("quick_onboarding_v2.feature_sms_abandoned"));
    }
    if (waConfirmation) {
      enabledFeatures.push(
        I18n.t("quick_onboarding_v2.feature_wa_confirmation"),
      );
    }
    if (waFulfilment) {
      enabledFeatures.push(I18n.t("quick_onboarding_v2.feature_wa_fulfillment"));
    }
    if (waAbandoned) {
      enabledFeatures.push(I18n.t("quick_onboarding_v2.feature_wa_abandoned"));
    }
    if (waCodVerification) {
      enabledFeatures.push(
        I18n.t("quick_onboarding_v2.feature_wa_cod_verification"),
      );
    }

    const shopPreviewName =
      shop?.name || shop?.shopify_domain || "Demo Store";

    // Which channels can the merchant test from here? Abandoned cart messages can't be sent
    // as a test (they need a real abandoned checkout), so a channel is testable only when one
    // of its other messages is on — sendOnboardingTest picks that one. With only abandoned
    // cart on, the test card is hidden and the preview on the right is all we show.
    const smsTestAvailable = smsConfirmation || smsFulfilment;
    const waTestAvailable = waConfirmation || waFulfilment || waCodVerification;
    const onlyAbandonedCart =
      (smsAbandoned || waAbandoned) && !smsTestAvailable && !waTestAvailable;
    const waApproved =
      (setting?.whatsappApprovalStatus ?? setting?.whatsapp_approval_status) ===
      "approved";

    const step4PreviewItems = collectStep4PreviewItems({
      smsConfirmation,
      smsFulfilment,
      smsAbandoned,
      waConfirmation,
      waFulfilment,
      waAbandoned,
      waCodVerification,
      setting,
      shopPreviewName,
    });

    const primaryPreviewRaw = step4PreviewItems.length
      ? pickPrimaryPreviewItem(step4PreviewItems)
      : null;
    const showViewAllPreviewsLink = step4PreviewItems.length > 1;

    const renderStep4PreviewVisual = (raw) => {
      if (raw.kind === "sms") {
        return (
          <Box width="100%" maxWidth="380px" marginInline="auto">
            <Box
              background="bg-surface"
              padding="400"
              borderRadius="300"
              borderWidth="025"
              borderColor="border"
              boxShadow="md"
            >
              <Box
                background="bg-fill-secondary"
                padding="300"
                borderRadius="200"
                maxWidth="100%"
              >
                <Text variant="bodySm" as="p" breakWord>
                  {raw.body}
                </Text>
              </Box>
              <Box paddingBlockStart="200">
                <Text
                  variant="bodySm"
                  tone="subdued"
                  alignment="end"
                  as="p"
                >
                  {I18n.t("quick_onboarding_v2.sms_preview_channel_label")}
                </Text>
              </Box>
            </Box>
          </Box>
        );
      }
      const imageStyle = {
        display: "block",
        maxWidth: "100%",
        maxHeight: "450px",
        marginInline: "auto",
        borderRadius: "12px",
        boxShadow: "0 4px 20px rgba(0,0,0,0.15)",
      };
      if (raw.waEvent) {
        return (
          <WhatsappNotificationPreview
            data={waLanguages}
            language={waLanguage}
            event={raw.waEvent}
            fallbackSrc={raw.src}
            alt={I18n.t(raw.altKey)}
            imageStyle={imageStyle}
          />
        );
      }
      return <img src={raw.src} alt={I18n.t(raw.altKey)} style={imageStyle} />;
    };

    return (
      <>
      <Card>
        <BlockStack gap="500">
          <InlineStack gap="200" blockAlign="center">
            <Button
              variant="plain"
              icon={ArrowLeftMinor}
              onClick={handleStep4Back}
              accessibilityLabel={I18n.t("quick_onboarding_v2.back")}
            />
            <Text variant="headingLg" as="h1">
              {I18n.t("quick_onboarding_v2.step4_title")}
            </Text>
          </InlineStack>

          <Text variant="bodyMd" tone="subdued">
            {I18n.t("quick_onboarding_v2.step4_subtitle")}
          </Text>

          {/* Two columns on desktop (md+); one column on mobile. GIF hidden on mobile via useBreakpoints. */}
          <InlineGrid
            columns={{ xs: 1, md: primaryPreviewRaw ? 2 : 1 }}
            gap="400"
          >
            {/* LEFT SIDE */}
            <BlockStack gap="400">
              {(waConfirmation || waFulfilment || waAbandoned || waCodVerification) && (
                <WhatsappLanguagePicker
                  data={waLanguages}
                  value={waLanguage}
                  onChange={handleWhatsappLanguageChange}
                />
              )}
              {/* Try it now: send a real message to the merchant's own phone before billing. Shown on top whenever a notification is enabled. */}
              {(smsTestAvailable || waTestAvailable) && (
                <Box
                  padding="500"
                  background="bg-surface-secondary"
                  borderRadius="300"
                >
                  <BlockStack gap="300">
                    <BlockStack gap="100">
                      <Text variant="headingMd">
                        {I18n.t("quick_onboarding_v2.test_card_title")}
                      </Text>
                      <Text variant="bodySm" tone="subdued">
                        {I18n.t("quick_onboarding_v2.test_card_subtitle")}
                      </Text>
                    </BlockStack>
                    <TextField
                      label={I18n.t("quick_onboarding_v2.test_phone_label")}
                      value={testPhone}
                      onChange={setTestPhone}
                      type="tel"
                      inputMode="tel"
                      autoComplete="tel"
                    />
                    <InlineStack gap="300">
                      {smsTestAvailable && (
                        <Button
                          onClick={() => sendOnboardingTest("sms")}
                          loading={testLoadingMode === "sms"}
                          disabled={testLoadingMode !== null}
                        >
                          {I18n.t("quick_onboarding_v2.test_send_sms")}
                        </Button>
                      )}
                      {waTestAvailable && (
                        <Button
                          onClick={() => sendOnboardingTest("whatsapp")}
                          loading={testLoadingMode === "whatsapp"}
                          disabled={testLoadingMode !== null}
                        >
                          {I18n.t("quick_onboarding_v2.test_send_whatsapp")}
                        </Button>
                      )}
                    </InlineStack>
                    {waTestAvailable && !waApproved && (
                      <Text variant="bodySm" tone="subdued">
                        {I18n.t(
                          "quick_onboarding_v2.test_whatsapp_approval_hint",
                        )}
                      </Text>
                    )}
                    {testBanner && (
                      <Banner
                        tone={testBanner.tone}
                        title={testBanner.title}
                        onDismiss={() => setTestBanner(null)}
                      >
                        {testBanner.message ? <p>{testBanner.message}</p> : null}
                      </Banner>
                    )}
                    {waTestAvailable && (
                      <Box
                        padding="300"
                        background="bg-surface"
                        borderRadius="200"
                      >
                        <Text variant="bodySm" tone="subdued">
                          {I18n.t("quick_onboarding_v2.test_brand_whatsapp_note")}
                        </Text>
                      </Box>
                    )}
                  </BlockStack>
                </Box>
              )}

              {onlyAbandonedCart && (
                <Banner tone="info">
                  <p>
                    {I18n.t("quick_onboarding_v2.abandoned_preview_only", {
                      defaultValue:
                        "Abandoned cart messages go out when a shopper leaves checkout without ordering, so they can't be sent as a test. The preview shows exactly what your customers will receive.",
                    })}
                  </p>
                </Banner>
              )}

              <Box
                padding="500"
                background="bg-surface-secondary"
                borderRadius="300"
              >
                <BlockStack gap="300">
                  <Text variant="headingMd">
                    {I18n.t("quick_onboarding_v2.your_setup")}
                  </Text>

                  <BlockStack gap="300">
                    {enabledFeatures.map((feature) => (
                      <InlineGrid
                        key={feature}
                        columns="auto minmax(0, 1fr)"
                        gap="200"
                        alignItems="start"
                      >
                        <Badge tone="success">
                          {I18n.t("quick_onboarding_v2.enabled")}
                        </Badge>
                        <Text as="p" variant="bodyMd" breakWord>
                          {feature}
                        </Text>
                      </InlineGrid>
                    ))}
                  </BlockStack>
                </BlockStack>
              </Box>

              <Box paddingBlockStart="200">
                <BlockStack gap="300">
                  <Button
                    fullWidth
                    variant="primary"
                    size="large"
                    onClick={handleEnableBilling}
                  >
                    {I18n.t("quick_onboarding_v2.activate_plan")}
                  </Button>
                  <Text
                    variant="bodyMd"
                    tone="subdued"
                    as="p"
                    alignment="center"
                  >
                    {I18n.t("quick_onboarding_v2.cancel_change_plans")}
                  </Text>
                </BlockStack>
              </Box>
            </BlockStack>

            {/* RIGHT SIDE notification preview – desktop only (Polaris useBreakpoints) */}
            {mdUp && primaryPreviewRaw && (
              <Box
                padding="400"
                background="bg-fill-secondary"
                borderRadius="300"
                minBlockSize="400px"
                display="flex"
                alignItems="center"
                justifyContent="center"
              >
                <BlockStack gap="300" inlineAlign="center">
                  <Box width="100%">
                    <Text
                      variant="bodySm"
                      as="p"
                      tone="subdued"
                      alignment="center"
                    >
                      {I18n.t(primaryPreviewRaw.captionKey)}
                    </Text>
                  </Box>
                  <Box
                    paddingBlockStart="100"
                    width="100%"
                    style={{ display: "flex", justifyContent: "center" }}
                  >
                    {renderStep4PreviewVisual(primaryPreviewRaw)}
                  </Box>
                  {showViewAllPreviewsLink && (
                    <Box paddingBlockStart="200">
                      <Button
                        variant="plain"
                        onClick={() => setAllPreviewsModalOpen(true)}
                      >
                        {I18n.t("quick_onboarding_v2.view_all_previews")}
                      </Button>
                    </Box>
                  )}
                </BlockStack>
              </Box>
            )}
          </InlineGrid>
        </BlockStack>
      </Card>
      <Modal
        open={allPreviewsModalOpen}
        onClose={() => setAllPreviewsModalOpen(false)}
        title={
          <div style={{ width: "100%", textAlign: "center" }}>
            {I18n.t("quick_onboarding_v2.all_previews_title")}
          </div>
        }
        primaryAction={{
          content: I18n.t("quick_onboarding_v2.activate_plan"),
          onAction: () => {
            setAllPreviewsModalOpen(false);
            handleEnableBilling({ preventDefault: () => {} });
          },
        }}
      >
        <Modal.Section>
          <Scrollable style={{ maxHeight: "min(70vh, 560px)" }}>
            <BlockStack gap="500" inlineAlign="center">
              {step4PreviewItems.map((raw, index) => (
                <BlockStack
                  key={raw.id}
                  gap="300"
                  inlineAlign="center"
                >
                  <Box width="100%">
                    <Text
                      variant="headingSm"
                      as="h3"
                      alignment="center"
                    >
                      {I18n.t(raw.captionKey)}
                    </Text>
                  </Box>
                  <Box
                    width="100%"
                    display="flex"
                    justifyContent="center"
                  >
                    {renderStep4PreviewVisual(raw)}
                  </Box>
                  {index < step4PreviewItems.length - 1 ? (
                    <Box width="100%">
                      <Divider />
                    </Box>
                  ) : null}
                </BlockStack>
              ))}
            </BlockStack>
          </Scrollable>
        </Modal.Section>
      </Modal>
      </>
    );
  };

  const renderCurrentStep = () => {
    switch (currentStep) {
      case 1:
        return renderStep1();
      case 2:
        return renderStep2();
      case 3:
        return renderStep3();
      case 4:
        return renderStep4();
      default:
        return renderStep1();
    }
  };

  const getStepTitle = () => {
    switch (currentStep) {
      case 1:
        return I18n.t("quick_onboarding_v2.step_title_installed");
      case 2:
        return I18n.t("quick_onboarding_v2.step_title_features");
      case 3:
        return I18n.t("quick_onboarding_v2.step_title_extension");
      case 4:
        return I18n.t("quick_onboarding_v2.step_title_almost_done");
      case 5:
        return I18n.t("quick_onboarding_v2.step_title_complete");
      default:
        return I18n.t("quick_onboarding_v2.step_title_setup");
    }
  };

  const renderSkeletonLoader = () => (
    <Page narrowWidth>
      <BlockStack gap="500">
        {/* Progress Bar Skeleton */}
        <Card>
          <BlockStack gap="300">
            <InlineStack align="space-between">
              <Box width="120px">
                <SkeletonBodyText lines={1} />
              </Box>
              <Box width="30px">
                <SkeletonBodyText lines={1} />
              </Box>
            </InlineStack>
            <Box
              background="bg-surface-secondary"
              borderRadius="full"
              minHeight="8px"
            />
          </BlockStack>
        </Card>

        {/* Main Content Skeleton */}
        <Card>
          <BlockStack gap="500">
            <SkeletonDisplayText size="medium" />
            <SkeletonBodyText lines={2} />

            <Box paddingBlockStart="200">
              <BlockStack gap="400">
                <Box
                  padding="400"
                  background="bg-surface-secondary"
                  borderRadius="200"
                >
                  <BlockStack gap="200">
                    <SkeletonBodyText lines={1} />
                    <Box paddingInlineStart="600">
                      <SkeletonBodyText lines={1} />
                    </Box>
                  </BlockStack>
                </Box>

                <Box
                  padding="400"
                  background="bg-surface-secondary"
                  borderRadius="200"
                >
                  <BlockStack gap="200">
                    <SkeletonBodyText lines={1} />
                    <Box paddingInlineStart="600">
                      <SkeletonBodyText lines={1} />
                    </Box>
                  </BlockStack>
                </Box>
              </BlockStack>
            </Box>

            <Box paddingBlockStart="400">
              <InlineStack align="end">
                <Box
                  width="100px"
                  minHeight="36px"
                  background="bg-surface-secondary"
                  borderRadius="200"
                />
              </InlineStack>
            </Box>
          </BlockStack>
        </Card>
      </BlockStack>
    </Page>
  );

  if (isLoading) {
    return renderSkeletonLoader();
  }

  return (
    <Page narrowWidth={currentStep !== 2}>
      <BlockStack gap="500">
        <Card>
          <BlockStack gap="300">
            <InlineStack align="space-between">
              <Text variant="bodySm" as="p" tone="subdued">
                {I18n.t("quick_onboarding_v2.step_of", {
                  current: currentStep,
                  title: getStepTitle(),
                })}
              </Text>
              <Text variant="bodySm" as="p" tone="subdued">
                {progressValues[currentStep]}%
              </Text>
            </InlineStack>
            <ProgressBar
              progress={progressValues[currentStep]}
              size="small"
              tone="success"
            />
          </BlockStack>
        </Card>

        {renderCurrentStep()}
      </BlockStack>
    </Page>
  );
};

export default QuickOnboardingV2;
