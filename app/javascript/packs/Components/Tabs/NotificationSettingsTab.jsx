import React, {
  useState,
  useContext,
  useEffect,
  useCallback,
  useRef,
} from "react";
// 1. Correct Import for App Bridge v4
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import { StoreContext } from "../../Context/Store.jsx";
import Api from "../../Services/Api.js";
import {
  Card,
  InlineStack,
  Checkbox,
  DataTable,
  Tabs,
  Link,
  TextField,
  Select,
  Button,
  Banner,
  FormLayout,
  Text,
  BlockStack,
  List,
  RadioButton,
  Box,
} from "@shopify/polaris";
import useApi from "../../Hooks/useApi.js";
import "../../../../assets/stylesheets/notification.css";
import EnableWhatsAppComp from "../EnableWhatsAppComp.jsx";
import I18n from "../../i18n-lang.js";
import { MessageCircle, MessageSquare } from "lucide-react";
import CommonModal from "../CommonModal.jsx";
import FreeWalletBalance from "../FreeWalletBalance.jsx";
import SmsTemplateManager from "./SmsTemplateManager.jsx";
import { debugLog } from "../../Modal/utilities/otpUtils.js";
import styled from "styled-components";
import { navigateTo } from "../../../utils/navigate";
import {
  useWhatsappLanguages,
  WhatsappLanguagePicker,
  WhatsappNotificationPreview,
  WA_PREVIEW_EVENTS,
  saveWhatsappLanguage,
} from "../WhatsappLanguage/WhatsappLanguage.jsx";

const SelectButton = styled(Button)`
  margin-top: 12px;
  background-color: #111827;
  color: white;
  border: none;
  padding: 8px 16px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 14px;
  &:disabled {
    background-color: #9ca3af;
    cursor: not-allowed;
    opacity: 0.6;
  }
`;

const Container = styled.div`
  width: 100%;
  margin: 0 auto;
`;

const PreviewIconsContainer = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
`;

const NotificationSettingsTab = () => {
  const shopify = useAppBridge(); // Initialize v4 App Bridge
  const {
    contextualBar: [contextualBar, setContextualBar],
    plan: [plan],
    shop: [shop],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    tab: [tab, setTab],
    loading: [, setLoading],
  } = useContext(StoreContext);

  // India shops don't get the SMS template approval workflow.
  const isIndiaShop = shop?.country_code === "IN";

  // Local state for template focus (not in StoreContext)
  const [templateFocus, setTemplateFocus] = useState(false);
  // Theme embed status for the "finish setup" nudge (null = unknown/loading).
  const [themeEmbedActive, setThemeEmbedActive] = useState(null);
  const [smsTemplateQuery, setSmsTemplateQuery] = useState(() => {
    try {
      return (
        new URLSearchParams(window.location.search).get("smsTemplate") || ""
      );
    } catch {
      return "";
    }
  });
  const [selectedNotificationSubTab, setSelectedNotificationSubTab] = useState(
    () => {
      try {
        return new URLSearchParams(window.location.search).get("smsTemplate") &&
          !isIndiaShop
          ? 1
          : 0;
      } catch {
        return 0;
      }
    },
  );

  const [isDirty, setIsDirty] = useState(false);
  const { data: waLanguages, reload: reloadWaLanguages } = useWhatsappLanguages();
  const [waLanguageSaving, setWaLanguageSaving] = useState(false);
  // Saved straight away (not through the Save bar): the language lives on settings, the
  // "merchant chose it" flag on additional_settings.
  const handleWhatsappLanguageChange = (value) => {
    const previous = setting?.whatsappLanguageCode;
    setSetting((current) => ({ ...current, whatsappLanguageCode: value }));
    setWaLanguageSaving(true);
    saveWhatsappLanguage(value)
      .then(() => reloadWaLanguages())
      .catch((err) => {
        console.error("Error saving WhatsApp language:", err);
        setSetting((current) => ({ ...current, whatsappLanguageCode: previous }));
      })
      .finally(() => setWaLanguageSaving(false));
  };
  const [notifBanner, setNotifBanner] = useState(null);
  const [resendToast, setResendToast] = useState(false);
  const [errorResponseTxt, setErrorResponseTxt] = useState("");
  const [wpButtonName, setWpButtonName] = useState("");
  const [apiInProgress, setApiInProgress] = useState(false);
  const [showDiscount, setShowDiscount] = useState(
    setting?.acWhatsappDiscoutEnabled || false,
  );

  const settingRef = useRef(setting);
  useEffect(() => {
    settingRef.current = setting;
  }, [setting]);

  // Track isDirty based on contextualBar
  useEffect(() => {
    setIsDirty(contextualBar);
  }, [contextualBar]);

  const options = [
    { label: I18n.t("admin.dont_send"), value: "-1" },
    { label: I18n.t("admin.3_minutes"), value: "3" },
    { label: I18n.t("admin.5_minutes"), value: "5" },
    { label: I18n.t("admin.10_minutes"), value: "10" },
    { label: I18n.t("admin.15_minutes"), value: "15" },
    { label: I18n.t("admin.30_minutes"), value: "30" },
    { label: I18n.t("admin.60_minutes"), value: "60" },
    { label: I18n.t("admin.12_hours"), value: "720" },
    { label: I18n.t("admin.24_hours"), value: "1440" },
    { label: I18n.t("admin.48_hours"), value: "2880" },
    { label: I18n.t("admin.72_hours"), value: "4320" },
  ];

  const first_purchase_options = [
    { label: I18n.t("admin.immediately"), value: "-1" },
    { label: I18n.t("admin.30_minutes"), value: "30" },
    { label: I18n.t("admin.60_minutes"), value: "60" },
    { label: I18n.t("admin.12_hours"), value: "720" },
    { label: I18n.t("admin.24_hours"), value: "1440" },
    { label: I18n.t("admin.2_days"), value: "2880" },
    { label: I18n.t("admin.7_days"), value: "10080" },
    { label: I18n.t("admin.15_days"), value: "21600" },
    { label: I18n.t("admin.30_days"), value: "43200" },
  ];

  const discountOptions = [
    { label: I18n.t("admin.offer_no_discount"), value: "0" },
    { label: I18n.t("admin.offer_discount"), value: "1" },
  ];

  const whatsappEnabledCountry = useState(
    process.env.WHATSAPP_COUNTRIES.split(",").includes(shop.country_code),
  );

  const setDefaultDiscountType = () => {
    const key = "selectedDiscount";
    const value = setting.acWhatsappDiscoutEnabled ? "1" : "0";
    const newSetting = { ...setting, [key]: value };
    setSetting(newSetting);
  };

  useEffect(() => {
    refreshSettings();
    setDefaultDiscountType();
    setting.whatsappApprovalStatus == "send_request"
      ? setWpButtonName(I18n.t("admin.request_whatsapp_approval"))
      : setWpButtonName(I18n.t("admin.whatsapp_approval_status"));
    checkWhatsappIntegrationStatus();
  }, []);

  // "Finish setup" nudge: if a checkout feature (OTP / partial payment) is on but the
  // storefront embed isn't active, the feature won't run — so prompt the merchant.
  // Covers anyone who skipped the theme step during onboarding, or never enabled it.
  useEffect(() => {
    const needsEmbed =
      Boolean(setting?.enablePreOrderOtp) ||
      Boolean(setting?.partialPaymentEnabled) ||
      Boolean(setting?.sendVerificationLinkOnly);
    if (!needsEmbed) {
      setThemeEmbedActive(null);
      return;
    }
    const domain =
      shop?.shopify_domain || window.shopOrigin || window.Shopify?.shop || "";
    if (!domain) return;
    let cancelled = false;
    fetch(
      `https://${process.env.APP_HOST}/order_confirmations/is_cod_king_block_enabled?shopifyDomain=${domain}`,
    )
      .then((r) => r.json())
      .then((data) => {
        if (!cancelled) setThemeEmbedActive(data?.assetEnabled === true);
      })
      .catch(() => {
        if (!cancelled) setThemeEmbedActive(null);
      });
    return () => {
      cancelled = true;
    };
  }, [
    setting?.enablePreOrderOtp,
    setting?.partialPaymentEnabled,
    setting?.sendVerificationLinkOnly,
    shop?.shopify_domain,
  ]);

  const openThemeEditorForEmbed = () => {
    const domain =
      shop?.shopify_domain || window.shopOrigin || window.Shopify?.shop || "";
    if (!domain) return;
    window.open(
      `https://${domain}/admin/themes/current/editor?context=apps&template=cart&activateAppId=99553eb5-bf07-4ce0-9263-7e5f10cab22c/app-embed`,
      "_blank",
    );
  };

  useEffect(() => {
    const readSmsTemplateQuery = () => {
      try {
        setSmsTemplateQuery(
          new URLSearchParams(window.location.search).get("smsTemplate") ||
            "",
        );
      } catch {
        setSmsTemplateQuery("");
      }
    };
    readSmsTemplateQuery();
    window.addEventListener("popstate", readSmsTemplateQuery);
    return () =>
      window.removeEventListener("popstate", readSmsTemplateQuery);
  }, []);

  useEffect(() => {
    if (smsTemplateQuery) setSelectedNotificationSubTab(1);
  }, [smsTemplateQuery]);

  const toggleResendctive = useCallback(
    () => setResendToast((resendToast) => !resendToast),
    [],
  );

  const resendToastMarkup = resendToast ? (
    <Banner
      title={errorResponseTxt}
      status="critical"
      onDismiss={toggleResendctive}
    />
  ) : null;

  const [modalActive, setModalActive] = useState(false);
  const [modalType, setModalType] = useState(null);
  const [modalContent, setModalContent] = useState({
    title: "",
    primaryActionContent: "",
    primaryAction: () => {},
    secondaryActionContent: I18n.t("admin.cancel"),
    children: null,
  });

  const [{ data: apiData, loading1, error }, saveSettings] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings`,
      method: "POST",
    },
    { manual: true },
  );

  const [whatsappIntegrationModalActive, setWhatsappIntegrationModalActive] =
    useState(false);
  const [whatsappIntegrationForm, setWhatsappIntegrationForm] = useState({
    email: "",
    phone_number: "",
    preferred_time: "",
  });
  const [whatsappIntegrationSubmitting, setWhatsappIntegrationSubmitting] =
    useState(false);
  const [whatsappIntegrationError, setWhatsappIntegrationError] =
    useState(null);
  const [whatsappIntegrationFieldErrors, setWhatsappIntegrationFieldErrors] =
    useState({
      email: "",
      phone_number: "",
    });
  const [whatsappIntegrationSuccess, setWhatsappIntegrationSuccess] =
    useState(false);
  const [whatsappIntegrationStatus, setWhatsappIntegrationStatus] =
    useState(null);
  const [whatsappIntegrationLoading, setWhatsappIntegrationLoading] =
    useState(true);

  const handleSettingChange = (key) => (value) => {
    const newSetting = { ...setting };
    if (key === "sms_retry1") {
      const retry2 = setting?.acSmsSchedule?.split(",")[1] || "-1";
      const retry3 = setting?.acSmsSchedule?.split(",")[2] || "-1";
      newSetting.acSmsSchedule = `${value},${retry2},${retry3}`;
    } else if (key === "sms_retry2") {
      const retry1 = setting?.acSmsSchedule?.split(",")[0] || "-1";
      const retry3 = setting?.acSmsSchedule?.split(",")[2] || "-1";
      newSetting.acSmsSchedule = `${retry1},${value},${retry3}`;
    } else if (key === "sms_retry3") {
      const retry1 = setting?.acSmsSchedule?.split(",")[0] || "-1";
      const retry2 = setting?.acSmsSchedule?.split(",")[1] || "-1";
      newSetting.acSmsSchedule = `${retry1},${retry2},${value}`;
    } else if (key === "wp_retry1") {
      const retry2 = setting?.acWhatsappSchedule?.split(",")[1] || "-1";
      const retry3 = setting?.acWhatsappSchedule?.split(",")[2] || "-1";
      newSetting.acWhatsappSchedule = `${value},${retry2},${retry3}`;
    } else if (key === "wp_retry2") {
      const retry1 = setting?.acWhatsappSchedule?.split(",")[0] || "-1";
      const retry3 = setting?.acWhatsappSchedule?.split(",")[2] || "-1";
      newSetting.acWhatsappSchedule = `${retry1},${value},${retry3}`;
    } else if (key === "wp_retry3") {
      const retry1 = setting?.acWhatsappSchedule?.split(",")[0] || "-1";
      const retry2 = setting?.acWhatsappSchedule?.split(",")[1] || "-1";
      newSetting.acWhatsappSchedule = `${retry1},${retry2},${value}`;
    } else if (key === "selectedDiscount") {
      const isEnabled = value === "1";
      newSetting.selectedDiscount = value;
      newSetting.acWhatsappDiscoutEnabled = isEnabled;
      newSetting.acWhatsappDiscount = isEnabled
        ? setting.acWhatsappDiscount
        : "";
      newSetting.acWhatsappDiscountCode = isEnabled
        ? setting.acWhatsappDiscountCode
        : "";
      setShowDiscount(isEnabled);
    } else {
      newSetting[key] = value;
    }

    if (key === "abandonedCartEnabled") {
      newSetting.acSmsSchedule = value ? "3,-1,-1" : "-1,-1,-1";
    }

    if (key === "acWhatsappDiscoutEnabled" || key === "acWhatsapp") {
      newSetting.acWhatsappSchedule = value ? "3,-1,-1" : "-1,-1,-1";
    }

    setSetting(newSetting);
    setIsDirty(true);
    if (!contextualBar) setContextualBar(true);
  };

  const handleSubmit = useCallback(async () => {
    setApiInProgress(true);
    setLoading(true);
    try {
      const response = await Api.post("/settings", settingRef.current);
      setIsDirty(false);
      setSetting(response.data);
      setOriginalSetting(response.data);
      setContextualBar(false);
      shopify.toast.show(I18n.t("admin.settings_saved"));
    } catch (error) {
      debugLog(error);
    } finally {
      setLoading(false);
      setApiInProgress(false);
    }
  }, [shopify, setSetting, setOriginalSetting, setContextualBar, setIsDirty]);

  const handleDiscard = useCallback(() => {
    const cloned = JSON.parse(JSON.stringify(originalSetting));
    setSetting(cloned);
    setIsDirty(false);
    setShowDiscount(cloned.acWhatsappDiscoutEnabled);
    setContextualBar(false);
  }, [originalSetting, setSetting, setContextualBar]);

  const handleTestSMS = (type) => {
    setApiInProgress(true);
    Api.post("/settings/test_notification", {
      type,
      mode: "sms",
      shop_id: shop.id,
    })
      .then((res) => {
        if (res.data.success) {
          setNotifBanner({
            status: "success",
            title: I18n.t("admin.test_sms_success"),
            children: `${I18n.t("admin.message_sent_successfully")} ${
              res.data.number
            }`,
          });
        } else {
          throw new Error("Test failed");
        }
      })
      .catch((error) => {
        setNotifBanner({
          status: "critical",
          title: I18n.t("admin.test_sms_failed"),
          children:
            error.response?.data?.error || I18n.t("admin.something_went_wrong"),
        });
      })
      .finally(() => {
        setApiInProgress(false);
      });
  };

  const handleTestWhatsApp = (type) => {
    setApiInProgress(true);
    Api.post("/settings/test_notification", {
      type,
      mode: "whatsapp",
      shop_id: shop.id,
    })
      .then((res) => {
        if (res.data.success) {
          setNotifBanner({
            status: "success",
            title: I18n.t("admin.test_whatsapp_success"),
            children: `${I18n.t("admin.message_sent_successfully")} ${
              res.data.number
            }`,
          });
        } else {
          throw new Error("Test failed");
        }
      })
      .catch((error) => {
        setNotifBanner({
          status: "critical",
          title: I18n.t("admin.test_whatsapp_failed"),
          children:
            error.response?.data?.error || I18n.t("admin.something_went_wrong"),
        });
      })
      .finally(() => {
        setApiInProgress(false);
      });
  };

  const [{ data, loading: settingsLoading }, refetchSettings] = useApi(
    {
      url: "/settings/setting",
      method: "get",
    },
    { manual: true },
  );

  const refreshSettings = () => {
    refetchSettings()
      .then((resp) => {
        if (resp.status === 200) {
          setSetting(resp.data.setting);
        }
      })
      .catch((error) => {});
  };

  const checkWhatsappIntegrationStatus = async () => {
    setWhatsappIntegrationLoading(true);
    try {
      const response = await Api.get(
        "/api/whatsapp_number_integration_requests/current_status",
      );
      if (response.data) {
        setWhatsappIntegrationStatus(response.data);
      } else {
        setWhatsappIntegrationStatus({
          hasRequest: false,
          status: null,
          canSubmitNew: true,
        });
      }
    } catch (error) {
      console.error("Error checking WhatsApp integration status:", error);
      setWhatsappIntegrationStatus({
        hasRequest: false,
        status: null,
        canSubmitNew: true,
      });
    } finally {
      setWhatsappIntegrationLoading(false);
    }
  };

  const isEnterpriseOrIndiaBudget = () => {
    const planName = plan?.name?.toLowerCase() || "";
    return planName.includes("enterprise") || planName.includes("india_budget");
  };

  const handleOpenSMSModal = () => {
    const content = (
      <Card sectioned title={I18n.t("admin.select_time_preference_sms")}>
        <Select
          label={I18n.t("admin.send_first_abandoned_sms_after")}
          options={options}
          helpText={I18n.t("admin.set_time_first_message")}
          onChange={handleSettingChange("sms_retry1")}
          value={
            setting?.acSmsSchedule?.split(",").length >= 1
              ? setting?.acSmsSchedule?.split(",")[0]
              : "-1"
          }
          autoFocus
        />
        <Select
          label={I18n.t("admin.send_second_abandoned_sms_after")}
          options={options}
          helpText={I18n.t("admin.set_time_second_message")}
          onChange={handleSettingChange("sms_retry2")}
          value={
            setting?.acSmsSchedule?.split(",").length >= 2
              ? setting?.acSmsSchedule?.split(",")[1]
              : "-1"
          }
        />
        <Select
          label={I18n.t("admin.send_third_abandoned_sms_after")}
          options={options}
          helpText={I18n.t("admin.set_time_third_message")}
          onChange={handleSettingChange("sms_retry3")}
          value={
            setting?.acSmsSchedule?.split(",").length >= 3
              ? setting?.acSmsSchedule?.split(",")[2]
              : "-1"
          }
        />
      </Card>
    );

    setModalContent({
      title: I18n.t("admin.sms_time_preference"),
      primaryActionContent: I18n.t("admin.close"),
      primaryAction: () => setModalActive(false),
      children: content,
    });
    setModalType("sms_schedule");
    setModalActive(true);
  };

  const handleOpenWhatsAppScheduleModal = () => {
    const content = (
      <Card
        className="modal-image"
        sectioned
        title={I18n.t("admin.select_time_preference_whatsapp")}
      >
        <Banner status="warning" title={I18n.t("admin.each_reminder_warning")}>
          <div
            dangerouslySetInnerHTML={{
              __html: I18n.t("admin.meta_policy_warning"),
            }}
          />
        </Banner>
        <br />
        <Select
          label={I18n.t("admin.send_first_abandoned_whatsapp_after")}
          options={options}
          helpText={I18n.t("admin.set_time_first_whatsapp")}
          onChange={handleSettingChange("wp_retry1")}
          value={
            setting?.acWhatsappSchedule?.split(",").length >= 1
              ? setting?.acWhatsappSchedule?.split(",")[0]
              : "-1"
          }
          autoFocus
        />
        <br />
        <Select
          label={I18n.t("admin.send_second_abandoned_whatsapp_after")}
          options={options}
          helpText={I18n.t("admin.set_time_second_whatsapp")}
          onChange={handleSettingChange("wp_retry2")}
          value={
            setting?.acWhatsappSchedule?.split(",").length >= 2
              ? setting?.acWhatsappSchedule?.split(",")[1]
              : "-1"
          }
        />
        <br />
        <Select
          label={I18n.t("admin.send_third_abandoned_whatsapp_after")}
          options={options}
          helpText={I18n.t("admin.set_time_third_whatsapp")}
          onChange={handleSettingChange("wp_retry3")}
          value={
            setting?.acWhatsappSchedule?.split(",").length >= 3
              ? setting?.acWhatsappSchedule?.split(",")[2]
              : "-1"
          }
        />
      </Card>
    );

    setModalContent({
      title: I18n.t("admin.whatsapp_time_preference"),
      primaryActionContent: I18n.t("admin.close"),
      primaryAction: () => setModalActive(false),
      children: content,
    });
    setModalType("whatsapp_schedule");
    setModalActive(true);
  };

  const handleOpenWhatsAppFirstTimeModal = () => {
    const content = (
      <>
        <Card
          className="modal-image"
          sectioned
          title={I18n.t("admin.first_time_purchase_config")}
        >
          <br />
          <Select
            label={I18n.t("admin.schedule_time_first_purchase")}
            options={first_purchase_options}
            helpText={I18n.t("admin.sends_whatsapp_after_time")}
            onChange={handleSettingChange("firstPurchaseSchedule")}
            value={
              setting?.firstPurchaseSchedule?.split(",").length >= 1
                ? setting?.firstPurchaseSchedule?.split(",")[0]
                : "-1"
            }
            autoFocus
          />
        </Card>
        <Card
          className="modal-image"
          sectioned
          title={I18n.t("admin.configure_discount_settings")}
        >
          <FormLayout>
            <TextField
              label={
                <span
                  dangerouslySetInnerHTML={{
                    __html: I18n.t("admin.discount_value"),
                  }}
                />
              }
              placeholder={I18n.t("admin.10_percent")}
              value={setting?.firstPurchaseDiscountOff}
              helpText={I18n.t("admin.for_example_discount")}
              onChange={handleSettingChange("firstPurchaseDiscountOff")}
              style={{ width: "50%" }}
            />
            <TextField
              label={
                <span
                  dangerouslySetInnerHTML={{
                    __html: I18n.t("admin.discount_code"),
                  }}
                />
              }
              placeholder={I18n.t("admin.10_percent")}
              value={setting?.firstPurchaseDiscountCode}
              helpText={I18n.t("admin.for_example_discount_code")}
              onChange={handleSettingChange("firstPurchaseDiscountCode")}
            />
          </FormLayout>
        </Card>
      </>
    );

    setModalContent({
      title: I18n.t("admin.first_time_purchase_config"),
      primaryActionContent: I18n.t("admin.close"),
      primaryAction: () => setModalActive(false),
      children: content,
    });
    setModalType("whatsapp_first_time");
    setModalActive(true);
  };

  const handleOpenWhatsAppDiscountModal = () => {
    const content = (
      <Card
        className="modal-image"
        sectioned
        title={I18n.t("admin.whatsapp_discount_config")}
      >
        <FormLayout>
          <RadioButton
            label={I18n.t("admin.offer_discount")}
            name="whatsappDiscountToggle"
            checked={setting?.acWhatsappDiscoutEnabled}
            onChange={() => {
              setSetting({
                ...setting,
                selectedDiscount: "1",
                acWhatsappDiscoutEnabled: true,
              });
              setShowDiscount(true);
            }}
          />
          <RadioButton
            label={I18n.t("admin.offer_no_discount")}
            name="whatsappDiscountToggle"
            checked={!setting?.acWhatsappDiscoutEnabled}
            onChange={() => {
              setSetting({
                ...setting,
                selectedDiscount: "0",
                acWhatsappDiscoutEnabled: false,
              });
              setShowDiscount(false);
            }}
          />
        </FormLayout>
        <br />
        {showDiscount && (
          <FormLayout>
            <TextField
              label={I18n.t("admin.discount_value")}
              value={setting?.acWhatsappDiscount}
              helpText={I18n.t("admin.for_example_discount")}
              onChange={handleSettingChange("acWhatsappDiscount")}
            />
            <TextField
              label={I18n.t("admin.discount_code")}
              value={setting?.acWhatsappDiscountCode}
              helpText={I18n.t("admin.for_example_discount_code")}
              onChange={handleSettingChange("acWhatsappDiscountCode")}
            />
          </FormLayout>
        )}
      </Card>
    );

    setModalContent({
      title: I18n.t("admin.whatsapp_discount_config"),
      primaryActionContent: I18n.t("admin.close"),
      primaryAction: () => setModalActive(false),
      children: content,
    });
    setModalType("whatsapp_discount");
    setModalActive(true);
  };

  useEffect(() => {
    const openModal = () => {
      switch (modalType) {
        case "whatsapp_schedule":
          handleOpenWhatsAppScheduleModal();
          break;
        case "whatsapp_discount":
          handleOpenWhatsAppDiscountModal();
          break;
        case "sms_schedule":
          handleOpenSMSModal();
          break;
        case "whatsapp_first_time":
          handleOpenWhatsAppFirstTimeModal();
          break;
        default:
          break;
      }
    };
    if (modalActive) {
      openModal();
    }
  }, [modalActive, modalType, setting]);

  const handleWhatsappIntegrationSubmit = async () => {
    const fieldErrors = {
      email: whatsappIntegrationForm.email ? "" : "This is required",
      phone_number: whatsappIntegrationForm.phone_number
        ? ""
        : "This is required",
    };
    if (fieldErrors.email || fieldErrors.phone_number) {
      setWhatsappIntegrationFieldErrors(fieldErrors);
      return;
    }
    setWhatsappIntegrationFieldErrors({ email: "", phone_number: "" });
    setWhatsappIntegrationSubmitting(true);
    setWhatsappIntegrationError(null);

    try {
      const response = await Api.post(
        "/api/whatsapp_number_integration_requests",
        {
          whatsapp_number_integration_request: whatsappIntegrationForm,
        },
      );

      if (response.data.success) {
        setWhatsappIntegrationSuccess(true);
        setWhatsappIntegrationForm({
          email: "",
          phone_number: "",
          preferred_time: "",
        });
        await checkWhatsappIntegrationStatus();
        setTimeout(() => {
          setWhatsappIntegrationModalActive(false);
          setWhatsappIntegrationSuccess(false);
        }, 3000);
      }
    } catch (error) {
      if (error.response?.status === 429) {
        setWhatsappIntegrationError(
          error.response?.data?.message ||
            I18n.t("whatsapp_integration.rate_limited", {
              hours: error.response?.data?.hours_remaining || 24,
            }),
        );
      } else {
        setWhatsappIntegrationError(
          error.response?.data?.errors?.join(", ") ||
            error.response?.data?.message ||
            I18n.t("whatsapp_integration.error_submitting"),
        );
      }
    } finally {
      setWhatsappIntegrationSubmitting(false);
    }
  };

  const handleOpenWhatsappIntegrationModal = () => {
    setWhatsappIntegrationModalActive(true);
    setWhatsappIntegrationError(null);
    setWhatsappIntegrationFieldErrors({ email: "", phone_number: "" });
    setWhatsappIntegrationSuccess(false);
  };

  const handleNavigateToPlans = () => {
    navigateTo("/subscription");
  };

  return (
    <Container>
      {/* Declarative SaveBar for App Bridge v4 */}
      <SaveBar data-save-bar open={isDirty}>
        <button
          variant="primary"
          onClick={handleSubmit}
          loading={apiInProgress ? "" : undefined}
          disabled={apiInProgress}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>{I18n.t("admin.discard")}</button>
      </SaveBar>

      {!window.location.href.includes("quick-onboarding") && (
        <FreeWalletBalance />
      )}
      {resendToastMarkup}
      {themeEmbedActive === false && (
        <>
          <Banner
            status="warning"
            title={I18n.t("admin.theme_embed_reminder_title")}
            action={{
              content: I18n.t("admin.theme_embed_open_editor"),
              onAction: openThemeEditorForEmbed,
            }}
          >
            <p>{I18n.t("admin.theme_embed_reminder_body")}</p>
          </Banner>
          <br />
        </>
      )}
      {setting.whatsappApprovalStatus !== "approved" &&
        (setting.confirmationWhatsapp ||
          setting.fulfilmentWhatsapp ||
          setting.acWhatsapp ||
          setting.firstPurchaseWhatsappEnabled ||
          setting.sendVerificationLinkOnly) && (
          <Banner
            status="warning"
            title={I18n.t("admin.whatsapp_approval_pending")}
          >
            <div
              dangerouslySetInnerHTML={{
                __html: I18n.t("admin.whatsapp_approval_message"),
              }}
            />
          </Banner>
        )}

      <br />

      <InlineStack spacing="loose">
        <Card sectioned className="settings-card">
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
            }}
          >
            <Text variant="headingMd" as="h2" style={{ textAlign: "left" }}>
              {I18n.t("admin.customer_notifications")}
            </Text>
            <SelectButton
              onClick={() => {
                setModalContent({
                  title: I18n.t("admin.whatsapp_approval_status"),
                  primaryActionContent: I18n.t("admin.close"),
                  primaryAction: () => {
                    setModalActive(false);
                  },
                  children: (
                    <p>
                      <EnableWhatsAppComp />
                    </p>
                  ),
                });
                setModalType("approve_whatsapp");
                setModalActive(true);
              }}
              style={{ textAlign: "right" }}
            >
              {wpButtonName}
            </SelectButton>
          </div>
          <Tabs
            tabs={[
              { id: "customer-notifications", content: I18n.t("admin.customer_notifications") },
              ...(isIndiaShop
                ? []
                : [
                    {
                      id: "sms-template-approvals",
                      content: I18n.t(
                        "notification_settings_tab.sms_template_management"
                      ),
                    },
                  ]),
            ]}
            selected={selectedNotificationSubTab}
            onSelect={setSelectedNotificationSubTab}
          />

          {selectedNotificationSubTab === 0 || isIndiaShop ? (
            <>
          <p>
            <small>
              <b>{I18n.t("admin.build_brand_trust")}</b>
            </small>
          </p>

          <Box maxWidth="420px" paddingBlockStart="200" paddingBlockEnd="200">
            <WhatsappLanguagePicker
              data={waLanguages}
              value={setting?.whatsappLanguageCode}
              onChange={handleWhatsappLanguageChange}
              disabled={waLanguageSaving}
            />
          </Box>

          {notifBanner && (
            <Banner
              status={notifBanner.status}
              title={notifBanner.title}
              onDismiss={() => setNotifBanner(null)}
            >
              {notifBanner.children}
              <br />
              <b>{I18n.t("admin.change_number")}</b>
              <Link
                external
                onClick={() => window.$crisp.push(["do", "chat:open"])}
              >
                {I18n.t("notification_settings_tab.chat_with_us")}
              </Link>{" "}
            </Banner>
          )}

          <DataTable
            columnContentTypes={[
              "text",
              "text",
              "text",
              "text",
              "text",
              "text",
            ]}
            headings={[
              I18n.t("admin.notification_event_type"),
              I18n.t("admin.sms_notification"),
              I18n.t("admin.whatsapp_notification"),
              I18n.t("admin.preview"),
              I18n.t("admin.test_sms"),
              I18n.t("admin.test_whatsapp"),
            ]}
            rows={[
              [
                <div>
                  <p>
                    <b>{I18n.t("admin.order_confirmation")}</b>
                  </p>
                  <p>
                    <small>
                      {I18n.t("admin.order_confirmation_description")}
                    </small>
                  </p>
                </div>,
                <Checkbox
                  label=""
                  checked={setting?.confirmationSmsEnabled}
                  onChange={handleSettingChange("confirmationSmsEnabled")}
                />,
                <Checkbox
                  label=""
                  checked={setting?.confirmationWhatsapp}
                  onChange={handleSettingChange("confirmationWhatsapp")}
                />,
                <PreviewIconsContainer>
                  <MessageSquare
                    size={24}
                    className="icon-xl"
                    title={I18n.t("admin.preview_sms")}
                    aria-label={I18n.t("admin.preview_sms")}
                    onClick={() => {
                      setModalContent({
                        title: I18n.t("admin.sms_preview"),
                        primaryActionContent: I18n.t("admin.close"),
                        primaryAction: () => setModalActive(false),
                        children: (
                          <p>
                            <TextField
                              disabled={true}
                              onBlur={() => setTemplateFocus(false)}
                              focused={templateFocus}
                              label={I18n.t("admin.sms_preview")}
                              value={setting?.orderConfirmationTemplate}
                              placeholder={process.env.CONFIRMATION_TEMPLATE}
                              multiline={2}
                              maxLength={140}
                              showCharacterCount
                              helpText={
                                <>
                                  {I18n.t("admin.modifying_sms_template")}{" "}
                                  <Link
                                    external
                                    onClick={() =>
                                      window.$crisp.push(["do", "chat:open"])
                                    }
                                  >
                                    {I18n.t("admin.chat_with_us")}
                                  </Link>{" "}
                                  {I18n.t("admin.for_editing_template")}
                                </>
                              }
                            />
                          </p>
                        ),
                      });
                      setModalActive(true);
                      setModalType("order_confirmation_sms");
                    }}
                  />
                  &nbsp;
                  <MessageCircle
                    size={24}
                    className="icon-xl"
                    title={I18n.t("admin.preview_whatsapp")}
                    aria-label={I18n.t("admin.preview_whatsapp")}
                    onClick={() => {
                      setModalContent({
                        title: I18n.t("admin.whatsapp_preview"),
                        primaryActionContent: I18n.t("admin.close"),
                        primaryAction: () => setModalActive(false),
                        children: (
                          <WhatsappNotificationPreview
                            data={waLanguages}
                            language={setting?.whatsappLanguageCode}
                            event={WA_PREVIEW_EVENTS.orderConfirmation}
                            fallbackSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/x4SVNU.png?v=1701069271"
                            imageClassName="modal-image"
                          />
                        ),
                      });
                      setModalActive(true);
                      setModalType("order_confirmation_whatsapp");
                    }}
                  />
                </PreviewIconsContainer>,
                <SelectButton
                  onClick={() => handleTestSMS("order_confirmation")}
                  disabled={apiInProgress}
                >
                  {I18n.t("admin.test_sms")}
                </SelectButton>,
                <SelectButton
                  onClick={() => handleTestWhatsApp("order_confirmation")}
                  disabled={apiInProgress}
                >
                  {I18n.t("admin.test_whatsapp")}
                </SelectButton>,
              ],
              [
                <div>
                  <p>
                    <b>{I18n.t("admin.order_fulfilment_tracking")}</b>
                  </p>
                  <p>
                    <small>
                      {I18n.t("admin.order_fulfilment_description")}
                    </small>
                  </p>
                </div>,
                <Checkbox
                  label=""
                  checked={setting?.enableFulfilmentMessage}
                  onChange={handleSettingChange("enableFulfilmentMessage")}
                />,
                <Checkbox
                  label=""
                  checked={setting?.fulfilmentWhatsapp}
                  onChange={handleSettingChange("fulfilmentWhatsapp")}
                />,
                <PreviewIconsContainer>
                  <MessageSquare
                    size={24}
                    className="icon-xl"
                    title={I18n.t("admin.preview_sms")}
                    aria-label={I18n.t("admin.preview_sms")}
                    onClick={() => {
                      setModalContent({
                        title: I18n.t("admin.sms_preview"),
                        primaryActionContent: I18n.t("admin.close"),
                        primaryAction: () => setModalActive(false),
                        children: (
                          <p>
                            <TextField
                              disabled={true}
                              onBlur={() => setTemplateFocus(false)}
                              focused={templateFocus}
                              label={I18n.t("admin.sms_preview")}
                              value={setting?.fulfilmentTemplate}
                              placeholder={I18n.t(
                                "admin.fulfilment_template_placeholder",
                              )}
                              multiline={2}
                              maxLength={140}
                              showCharacterCount
                              helpText={
                                <>
                                  {I18n.t("admin.modifying_sms_template")}{" "}
                                  <Link
                                    external
                                    onClick={() =>
                                      window.$crisp.push(["do", "chat:open"])
                                    }
                                  >
                                    {I18n.t("admin.chat_with_us")}
                                  </Link>{" "}
                                  {I18n.t("admin.for_editing_template")}
                                </>
                              }
                            />
                          </p>
                        ),
                      });
                      setModalActive(true);
                      setModalType("order_fulfilment_sms");
                    }}
                  />
                  &nbsp;
                  <MessageCircle
                    size={24}
                    className="icon-xl"
                    title={I18n.t("admin.preview_whatsapp")}
                    aria-label={I18n.t("admin.preview_whatsapp")}
                    onClick={() => {
                      setModalContent({
                        title: I18n.t("admin.whatsapp_preview"),
                        primaryActionContent: I18n.t("admin.close"),
                        primaryAction: () => setModalActive(false),
                        children: (
                          <WhatsappNotificationPreview
                            data={waLanguages}
                            language={setting?.whatsappLanguageCode}
                            event={WA_PREVIEW_EVENTS.fulfilment}
                            fallbackSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/b.png?v=1701082382"
                            imageClassName="modal-image"
                          />
                        ),
                      });
                      setModalActive(true);
                      setModalType("order_fulfilment_whatsapp");
                    }}
                  />
                </PreviewIconsContainer>,
                <SelectButton
                  onClick={() => handleTestSMS("order_fulfilment")}
                  disabled={apiInProgress}
                >
                  {I18n.t("admin.test_sms")}
                </SelectButton>,
                <SelectButton
                  onClick={() => handleTestWhatsApp("order_fulfilment")}
                  disabled={apiInProgress}
                >
                  {I18n.t("admin.test_whatsapp")}
                </SelectButton>,
              ],
              [
                <div>
                  <p>
                    <b>{I18n.t("admin.abandoned_checkout")}</b>
                  </p>
                  <p>
                    <small>
                      {I18n.t("admin.abandoned_checkout_description")}{" "}
                      <b>{I18n.t("admin.increase_conversion_discount")}</b>{" "}
                    </small>
                  </p>
                </div>,
                <>
                  <Checkbox
                    label=""
                    checked={setting.abandonedCartEnabled}
                    onChange={handleSettingChange("abandonedCartEnabled")}
                  />
                  <br />
                  <Link onClick={handleOpenSMSModal}>
                    {I18n.t("admin.configure_reminders")}
                  </Link>
                </>,
                <>
                  <Checkbox
                    label=""
                    checked={setting.acWhatsapp}
                    onChange={handleSettingChange("acWhatsapp")}
                  />
                  <br />
                  <>
                    <Link onClick={() => handleOpenWhatsAppScheduleModal()}>
                      {I18n.t("admin.configure_reminders")}
                    </Link>
                    <br />
                    <Link
                      onClick={() => {
                        setModalType("whatsapp_discount");
                        setModalActive(true);
                      }}
                    >
                      {I18n.t("admin.configure_discount")}
                    </Link>
                  </>
                </>,
                <PreviewIconsContainer>
                  <MessageSquare
                    size={24}
                    className="icon-xl"
                    title={I18n.t("admin.preview_sms")}
                    aria-label={I18n.t("admin.preview_sms")}
                    onClick={() => {
                      setModalContent({
                        title: I18n.t("admin.sms_preview"),
                        primaryActionContent: I18n.t("admin.close"),
                        primaryAction: () => setModalActive(false),
                        children: (
                          <TextField
                            disabled={true}
                            onBlur={() => setTemplateFocus(false)}
                            focused={templateFocus}
                            label={I18n.t("admin.sms_preview")}
                            value={setting.abandonedTemplate}
                            onChange={handleSettingChange("abandonedTemplate")}
                            placeholder={I18n.t("admin.sms_placeholder")}
                            multiline={2}
                            maxLength={140}
                            showCharacterCount
                            helpText={
                              <>
                                {I18n.t("admin.modifying_sms_template")}{" "}
                                <Link
                                  external
                                  onClick={() =>
                                    window.$crisp.push(["do", "chat:open"])
                                  }
                                >
                                  {I18n.t("admin.chat_with_us")}
                                </Link>{" "}
                                {I18n.t("admin.for_editing_template")}
                              </>
                            }
                          />
                        ),
                      });
                      setModalActive(true);
                      setModalType("abandoned_checkout_sms");
                    }}
                  />
                  &nbsp;
                  <MessageCircle
                    size={24}
                    className="icon-xl"
                    title={I18n.t("admin.preview_whatsapp")}
                    aria-label={I18n.t("admin.preview_whatsapp")}
                    onClick={() => {
                      setModalContent({
                        title: I18n.t("admin.whatsapp_preview"),
                        primaryActionContent: I18n.t("admin.close"),
                        primaryAction: () => setModalActive(false),
                        children: (
                          <p>
                            {(() => {
                              if (setting.selectedDiscount === "1") {
                                return (
                                  <WhatsappNotificationPreview
                                    data={waLanguages}
                                    language={setting?.whatsappLanguageCode}
                                    event={WA_PREVIEW_EVENTS.abandonedCartDiscount}
                                    fallbackSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/WhatsApp_Image_2024-01-24_at_12.46.33_PM.jpg?v=1706080632"
                                    imageClassName="modal-image"
                                  />
                                );
                              } else {
                                return (
                                  <WhatsappNotificationPreview
                                    data={waLanguages}
                                    language={setting?.whatsappLanguageCode}
                                    event={WA_PREVIEW_EVENTS.abandonedCart}
                                    fallbackSrc="https://cdn.shopify.com/s/files/1/0655/2089/4070/files/whatsapp_abandon_preview.png?v=1774873052"
                                    imageClassName="modal-image"
                                  />
                                );
                              }
                            })()}
                          </p>
                        ),
                      });
                      setModalActive(true);
                      setModalType("preabandoned_checkout_whatsapp");
                    }}
                  />
                </PreviewIconsContainer>,
                <SelectButton
                  onClick={() => handleTestSMS("abandoned_checkout")}
                  disabled={apiInProgress}
                >
                  {I18n.t("admin.test_sms")}
                </SelectButton>,
                <SelectButton
                  onClick={() => handleTestWhatsApp("abandoned_checkout")}
                  disabled={apiInProgress}
                >
                  {I18n.t("admin.test_whatsapp")}
                </SelectButton>,
              ],
              [
                <div>
                  <p>
                    <b>{I18n.t("admin.first_time_purchase")}</b>
                  </p>
                  <p>
                    <small>
                      {I18n.t("admin.first_time_purchase_description")}
                      <b>{I18n.t("admin.increase_conversion_discount")}</b>{" "}
                    </small>
                  </p>
                </div>,
                <>
                  <div>N/A</div>
                </>,
                <>
                  <Checkbox
                    label=""
                    checked={setting.firstPurchaseWhatsappEnabled}
                    onChange={handleSettingChange(
                      "firstPurchaseWhatsappEnabled",
                    )}
                  />
                  <br />
                  <>
                    <Link onClick={() => handleOpenWhatsAppFirstTimeModal()}>
                      {I18n.t("admin.schedule_configure")}
                    </Link>
                  </>
                </>,
                <PreviewIconsContainer>
                  <MessageCircle
                    size={24}
                    className="icon-xl"
                    title={I18n.t("admin.preview_whatsapp")}
                    aria-label={I18n.t("admin.preview_whatsapp")}
                    onClick={() => {
                      setModalContent({
                        title: I18n.t("admin.whatsapp_preview"),
                        primaryActionContent: I18n.t("admin.close"),
                        primaryAction: () => setModalActive(false),
                        children: (
                          <p>
                            {(() => {
                              return (
                                <WhatsappNotificationPreview
                                  data={waLanguages}
                                  language={setting?.whatsappLanguageCode}
                                  event={WA_PREVIEW_EVENTS.firstPurchase}
                                  fallbackSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/first_time.jpg?v=1725947923"
                                  imageClassName="modal-image"
                                />
                              );
                            })()}
                          </p>
                        ),
                      });
                      setModalActive(true);
                      setModalType("preabandoned_checkout_whatsapp");
                    }}
                  />
                </PreviewIconsContainer>,
                <div></div>,
                <SelectButton
                  onClick={() => handleTestWhatsApp("first_time_purchase")}
                  disabled={apiInProgress}
                >
                  {I18n.t("admin.test_whatsapp")}
                </SelectButton>,
              ],
            ]}
          />
            </>
          ) : (
            <SmsTemplateManager
              shop={shop}
              plan={plan}
              initialTemplateKey={smsTemplateQuery || undefined}
            />
          )}
        </Card>
      </InlineStack>

      {/* WhatsApp Number Integration Section */}
      <br />
      <Card sectioned className="settings-card">
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
          }}
        >
          <Text variant="headingMd" as="h2" style={{ textAlign: "left" }}>
            {I18n.t("admin.send_from_your_number")}
          </Text>
          {!whatsappIntegrationLoading && (
            <SelectButton onClick={() => navigateTo("/features/whatsapp")}>
              {I18n.t("whatsapp_integration.integrate_whatsapp_number")}
            </SelectButton>
          )}
        </div>
        <p>
          <small>
            {I18n.t("whatsapp_integration.send_from_your_number_description")}
          </small>
        </p>
        {!whatsappIntegrationLoading &&
          whatsappIntegrationStatus?.hasRequest && (
            <Banner
              status={
                whatsappIntegrationStatus.status === "pending" ||
                whatsappIntegrationStatus.status === "submitted"
                  ? "info"
                  : whatsappIntegrationStatus.status === "approved"
                    ? "success"
                    : whatsappIntegrationStatus.status === "rejected"
                      ? "warning"
                      : "info"
              }
              title={I18n.t("whatsapp_integration.request_status_title")}
            >
              {whatsappIntegrationStatus.status === "pending" ||
              whatsappIntegrationStatus.status === "submitted"
                ? I18n.t("whatsapp_integration.request_submitted_wait_message")
                : whatsappIntegrationStatus.status === "approved"
                  ? I18n.t("whatsapp_integration.request_approved_message")
                  : whatsappIntegrationStatus.status === "rejected"
                    ? I18n.t("whatsapp_integration.request_rejected_message")
                    : I18n.t("whatsapp_integration.request_processing_message")}
            </Banner>
          )}
      </Card>

      <CommonModal
        open={modalActive}
        onClose={() => setModalActive(false)}
        title={modalContent.title}
        primaryActionContent={modalContent.primaryActionContent}
        primaryAction={modalContent.primaryAction}
      >
        {modalContent.children}
      </CommonModal>

      {/* WhatsApp Number Integration Modal */}
      <CommonModal
        open={whatsappIntegrationModalActive}
        onClose={() => {
          if (!whatsappIntegrationSubmitting) {
            setWhatsappIntegrationModalActive(false);
            setWhatsappIntegrationError(null);
            setWhatsappIntegrationFieldErrors({ email: "", phone_number: "" });
            setWhatsappIntegrationSuccess(false);
          }
        }}
        title={I18n.t("whatsapp_integration.integrate_whatsapp_number")}
        primaryActionContent={
          whatsappIntegrationSubmitting
            ? "Submitting..."
            : isEnterpriseOrIndiaBudget()
              ? I18n.t("whatsapp_integration.submit_request")
              : I18n.t("whatsapp_integration.upgrade_to_enterprise")
        }
        primaryAction={
          whatsappIntegrationSubmitting
            ? () => {}
            : isEnterpriseOrIndiaBudget()
              ? handleWhatsappIntegrationSubmit
              : handleNavigateToPlans
        }
      >
        {whatsappIntegrationSuccess ? (
          <Banner
            status="success"
            title={I18n.t("whatsapp_integration.request_submitted")}
          >
            {I18n.t("whatsapp_integration.request_submitted_message")}
          </Banner>
        ) : (
          <>
            {whatsappIntegrationError && (
              <Banner
                status="critical"
                title={I18n.t("whatsapp_integration.error")}
              >
                {whatsappIntegrationError}
              </Banner>
            )}

            {!isEnterpriseOrIndiaBudget() ? (
              <BlockStack gap="500">
                <Card sectioned>
                  <BlockStack gap="400">
                    <Text variant="headingMd" as="h3">
                      {I18n.t("whatsapp_integration.upgrade_required")}
                    </Text>
                    <Text>
                      {I18n.t(
                        "whatsapp_integration.upgrade_required_description",
                      )}
                    </Text>
                  </BlockStack>
                </Card>

                <Card sectioned>
                  <BlockStack gap="300">
                    <Text variant="headingSm" as="h4">
                      <strong>
                        {I18n.t("whatsapp_integration.upgrade_benefit_title")}
                      </strong>
                    </Text>
                    <List>
                      <List.Item>
                        {I18n.t("whatsapp_integration.upgrade_benefit_1")}
                      </List.Item>
                      <List.Item>
                        {I18n.t("whatsapp_integration.upgrade_benefit_2")}
                      </List.Item>
                      <List.Item>
                        {I18n.t("whatsapp_integration.upgrade_benefit_3")}
                      </List.Item>
                      <List.Item>
                        {I18n.t("whatsapp_integration.upgrade_benefit_4")}
                      </List.Item>
                    </List>
                  </BlockStack>
                </Card>
                <Card sectioned>
                  <BlockStack gap="300">
                    <Text variant="headingSm" as="h4">
                      <strong>
                        {I18n.t("whatsapp_integration.prerequisite_title")}
                      </strong>
                    </Text>
                    <Text>
                      {I18n.t("whatsapp_integration.prerequisite_description")}
                    </Text>
                  </BlockStack>
                </Card>
                <Card sectioned>
                  <BlockStack gap="300">
                    <Text variant="headingSm" as="h4">
                      <strong>
                        {I18n.t("whatsapp_integration.how_it_works_title")}
                      </strong>
                    </Text>
                    <List type="number">
                      <List.Item>
                        <BlockStack gap="100">
                          <Text>
                            {I18n.t("whatsapp_integration.step_1_upgrade")}
                          </Text>
                          <Text variant="bodySm" color="subdued">
                            {I18n.t("whatsapp_integration.step_1_upgrade_note")}
                          </Text>
                        </BlockStack>
                      </List.Item>
                      <List.Item>
                        {I18n.t("whatsapp_integration.step_2_request")}
                      </List.Item>
                      <List.Item>
                        {I18n.t("whatsapp_integration.step_3_coordinate")}
                      </List.Item>
                      <List.Item>
                        {I18n.t("whatsapp_integration.step_4_login")}
                      </List.Item>
                    </List>
                    <Text variant="bodySm" color="subdued">
                      {I18n.t("whatsapp_integration.integration_time_note")}
                    </Text>
                  </BlockStack>
                </Card>
              </BlockStack>
            ) : (
              <Card sectioned>
                <FormLayout>
                  <TextField
                    label={I18n.t("whatsapp_integration.email")}
                    type="email"
                    value={whatsappIntegrationForm.email}
                    onChange={(value) => {
                      setWhatsappIntegrationForm({
                        ...whatsappIntegrationForm,
                        email: value,
                      });
                      if (whatsappIntegrationFieldErrors.email) {
                        setWhatsappIntegrationFieldErrors((prev) => ({
                          ...prev,
                          email: "",
                        }));
                      }
                    }}
                    error={whatsappIntegrationFieldErrors.email || undefined}
                    required
                    helpText={I18n.t("whatsapp_integration.email_help")}
                  />
                  <TextField
                    label={I18n.t("whatsapp_integration.phone_number")}
                    type="tel"
                    value={whatsappIntegrationForm.phone_number}
                    onChange={(value) => {
                      setWhatsappIntegrationForm({
                        ...whatsappIntegrationForm,
                        phone_number: value,
                      });
                      if (whatsappIntegrationFieldErrors.phone_number) {
                        setWhatsappIntegrationFieldErrors((prev) => ({
                          ...prev,
                          phone_number: "",
                        }));
                      }
                    }}
                    error={
                      whatsappIntegrationFieldErrors.phone_number || undefined
                    }
                    required
                    helpText={I18n.t(
                      "whatsapp_integration.phone_number_help_updated",
                    )}
                  />
                  <TextField
                    label={I18n.t("whatsapp_integration.preferred_time")}
                    value={whatsappIntegrationForm.preferred_time}
                    onChange={(value) =>
                      setWhatsappIntegrationForm({
                        ...whatsappIntegrationForm,
                        preferred_time: value,
                      })
                    }
                    helpText={I18n.t(
                      "whatsapp_integration.preferred_time_help",
                    )}
                    placeholder={I18n.t(
                      "whatsapp_integration.preferred_time_placeholder",
                    )}
                  />
                </FormLayout>
                <br />
                <Text variant="bodyMd" color="subdued">
                  {I18n.t("whatsapp_integration.request_info")}
                </Text>
              </Card>
            )}
          </>
        )}
      </CommonModal>
    </Container>
  );
};

export default NotificationSettingsTab;
