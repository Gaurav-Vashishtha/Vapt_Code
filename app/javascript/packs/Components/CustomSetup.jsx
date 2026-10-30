import React, {
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  Banner,
  BlockStack,
  Box,
  Button,
  Card,
  Checkbox,
  Link,
  Collapsible,
  DataTable,
  Divider,
  FormLayout,
  Icon,
  InlineGrid,
  InlineStack,
  Modal,
  OptionList,
  Popover,
  Spinner,
  Tag,
  Text,
  TextField,
} from "@shopify/polaris";
import {
  ChevronDownMinor,
  ChevronUpMinor,
  DeleteMinor,
  EditMinor,
  ExternalMinor,
  PlusMinor,
} from "@shopify/polaris-icons";
import { useAppBridge } from "@shopify/app-bridge-react";
import { StoreContext } from "../Context/Store";
import I18n from "../i18n-lang";
import Api from "../Services/Api";
import {
  navigateTo,
  navigateToPreservingParams,
  safeInternalPath,
} from "../../utils/navigate";
import { getCustomSetupSections } from "../utils/customSetupSections";
import { useCodFormOn } from "../Pages/CodForm/components/OnboardingFormPreview";
import CustomSetupCodForm from "../Pages/CodForm/components/CustomSetupCodForm";
import { clearCustomSetupPending } from "../utils/customSetupFlow";
import { hasNoChargeId } from "../utils/shopUtils";
import {
  PARTIAL_RULE_EDIT_PAYLOAD_KEY,
  setPartialPaymentReturnPath,
} from "../utils/partialRuleEditPayload";
import useApi from "../Hooks/useApi";
import HexColorPicker from "./HexColorPicker";
import WidgetPreviewPanel from "./WidgetPreview/WidgetPreviewPanel";
import countryOptions from "./Country";

function isPreOrderOtpEnabled(setting) {
  if (!setting) return false;
  const v = setting.enablePreOrderOtp ?? setting.enable_pre_order_otp;
  return v === true || v === "true" || v === 1 || v === "1";
}

function isPartialPaymentEnabledForPreview(setting) {
  if (!setting) return false;
  return Boolean(
    setting.partialPaymentEnabled ?? setting.partial_payment_enabled,
  );
}

// Black or white, whichever reads better on the given hex colour.
function readableTextOn(hex) {
  const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(hex || "").trim());
  if (!m) return "#FFFFFF";
  let h = m[1];
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  const lin = (c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const luminance = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  return luminance > 0.4 ? "#000000" : "#FFFFFF";
}

// The brand colour drives the primary button, the promo banner and the
// order-summary / coupon sheet headers, each with text that stays readable.
function brandColorPatch(color) {
  const value = String(color || "").trim();
  if (!value) return {};
  const text = readableTextOn(value);
  return {
    prePrimaryButtonColor: value,
    prePrimaryButtonFontColor: text,
    promoBannerColor: value,
    promoTextColor: text,
  };
}

function openCrispSupportChat() {
  try {
    if (typeof window !== "undefined" && window.$crisp) {
      window.$crisp.push(["do", "chat:open"]);
    }
  } catch (_) {}
}

/**
 * Loads a sample product URL (same API as PreOrderSetting).
 * Shopify storefronts send frame-ancestors that forbid iframes in admin, so we never embed—open in new tab only.
 */
function PopupProductPreview({ shop, setting }) {
  const [
    { data: productUrlData, loading: productUrlLoading, error: productUrlError },
    getProductUrl,
  ] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/product_url`,
      method: "GET",
    },
    { manual: true },
  );

  useEffect(() => {
    getProductUrl();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- load once on mount (same as PreOrderSetting)
  }, []);

  const productUrl =
    productUrlData?.productUrl || productUrlData?.product_url;
  const apiReturnedError = Boolean(productUrlData?.error);
  const showErrorState =
    !productUrlLoading &&
    (productUrlError || apiReturnedError || (productUrlData && !productUrl));

  const openProductInNewTab = useCallback(() => {
    if (productUrl && !apiReturnedError) {
      window.open(productUrl, "_blank", "noopener,noreferrer");
    } else if (shop?.shopify_domain) {
      window.open(
        `https://${shop.shopify_domain}`,
        "_blank",
        "noopener,noreferrer",
      );
    }
  }, [apiReturnedError, productUrl, shop?.shopify_domain]);

  const otpOn = isPreOrderOtpEnabled(setting);
  const partialOn = isPartialPaymentEnabledForPreview(setting);
  let popupTestInstructionsKey = "custom_setup.popup_test_instructions_otp";
  if (otpOn && partialOn) {
    popupTestInstructionsKey = "custom_setup.popup_test_instructions_both";
  } else if (partialOn && !otpOn) {
    popupTestInstructionsKey = "custom_setup.popup_test_instructions_partial";
  }

  return (
    <Card>
      <Box padding="400">
        <BlockStack gap="400">
          <Text as="h3" variant="headingSm">
            {I18n.t("custom_setup.popup_preview_title")}
          </Text>
          <Banner tone="info">
            <BlockStack gap="500">
              <Text as="p" variant="bodyMd">
                {I18n.t("custom_setup.popup_preview_guide")}
              </Text>
              <Text as="p" variant="bodyMd">
                {I18n.t(popupTestInstructionsKey)}
              </Text>
              <Box paddingBlockStart="200">
                <BlockStack gap="300">
                  <Text as="p" variant="bodyMd">
                    {I18n.t("custom_setup.popup_test_if_missing")}
                  </Text>
                  <InlineStack align="start">
                    <Button onClick={openCrispSupportChat}>
                      {I18n.t("custom_setup.chat_now_support")}
                    </Button>
                  </InlineStack>
                </BlockStack>
              </Box>
            </BlockStack>
          </Banner>
          {productUrlLoading ? (
            <InlineStack gap="200" blockAlign="center">
              <Spinner size="small" />
              <Text as="span" tone="subdued" variant="bodySm">
                {I18n.t("custom_setup.popup_preview_loading")}
              </Text>
            </InlineStack>
          ) : null}
          {showErrorState ? (
            <Banner tone="warning">
              <p>{I18n.t("custom_setup.popup_preview_error")}</p>
            </Banner>
          ) : null}
          {productUrl && !apiReturnedError ? (
            <Box
              padding="400"
              background="bg-surface-secondary"
              borderColor="border"
              borderWidth="025"
              borderRadius="200"
            >
              <BlockStack gap="150">
                <Text as="p" variant="bodySm" fontWeight="semibold">
                  {I18n.t("custom_setup.popup_preview_link_label")}
                </Text>
                <Text
                  as="p"
                  variant="bodySm"
                  tone="subdued"
                  breakWord
                >
                  {productUrl}
                </Text>
              </BlockStack>
            </Box>
          ) : null}
          <InlineStack align="start">
            <Button
              variant="primary"
              icon={ExternalMinor}
              onClick={openProductInNewTab}
              disabled={!shop?.shopify_domain}
            >
              {I18n.t("custom_setup.popup_preview_open_product")}
            </Button>
          </InlineStack>
        </BlockStack>
      </Box>
    </Card>
  );
}

function SectionHeader({ open, title, subtitle, onToggle }) {
  const onKeyDown = (e) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      onToggle();
    }
  };

  return (
    <Box padding="400">
      <div
        role="button"
        tabIndex={0}
        aria-expanded={open}
        onClick={onToggle}
        onKeyDown={onKeyDown}
        style={{ cursor: "pointer" }}
      >
        <InlineStack align="space-between" blockAlign="start" gap="200">
          <BlockStack gap="100">
            <Text as="h2" variant="headingMd">
              {title}
            </Text>
            {subtitle ? (
              <Text as="p" tone="subdued" variant="bodySm">
                {subtitle}
              </Text>
            ) : null}
          </BlockStack>
          <Box paddingBlockStart="100">
            <Icon source={open ? ChevronUpMinor : ChevronDownMinor} tone="subdued" />
          </Box>
        </InlineStack>
      </div>
    </Box>
  );
}

const ENGAGEMENT_TEST_TYPES = {
  sms_order: { type: "order_confirmation", mode: "sms" },
  sms_fulfil: { type: "order_fulfilment", mode: "sms" },
  sms_ac: { type: "abandoned_checkout", mode: "sms" },
  wa_order: { type: "order_confirmation", mode: "whatsapp" },
  wa_fulfil: { type: "order_fulfilment", mode: "whatsapp" },
  wa_ac: { type: "abandoned_checkout", mode: "whatsapp" },
  wa_cod: { type: "cod_verification", mode: "whatsapp" },
};

const ENGAGEMENT_WA_PREVIEW_ORDER =
  "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/x4SVNU.png?v=1701069271";
const ENGAGEMENT_WA_PREVIEW_FULFIL =
  "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/b.png?v=1701082382";
const ENGAGEMENT_WA_PREVIEW_ABANDON =
  "https://cdn.shopify.com/s/files/1/0655/2089/4070/files/whatsapp_abandon_preview.png?v=1774873052";
const ENGAGEMENT_WA_PREVIEW_ABANDON_DISCOUNT =
  "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/WhatsApp_Image_2024-01-24_at_12.46.33_PM.jpg?v=1706080632";
const ENGAGEMENT_WA_PREVIEW_COD =
  "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/WhatsApp_Image_2025-11-04_at_12.39.52_PM.jpg?v=1762247089";

const SMS_TEMPLATE_PARAM_BY_TEST_KEY = {
  sms_order: "order_confirmation",
  sms_fulfil: "order_fulfilment",
  sms_ac: "abandoned_checkout",
};

function buildEngagementPreviewModel(testKey, setting) {
  if (testKey === "sms_order") {
    const body =
      (setting?.orderConfirmationTemplate ||
        setting?.order_confirmation_template ||
        "").trim() ||
      process.env.CONFIRMATION_TEMPLATE ||
      "";
    return {
      kind: "sms",
      title: I18n.t("admin.sms_preview"),
      body: body || I18n.t("admin.sms_placeholder"),
    };
  }
  if (testKey === "sms_fulfil") {
    const body =
      (setting?.fulfilmentTemplate ||
        setting?.fulfilment_template ||
        "").trim() ||
      I18n.t("admin.fulfilment_template_placeholder");
    return {
      kind: "sms",
      title: I18n.t("admin.sms_preview"),
      body,
    };
  }
  if (testKey === "sms_ac") {
    const body =
      (setting?.abandonedTemplate || setting?.abandoned_template || "").trim() ||
      I18n.t("admin.sms_placeholder");
    return {
      kind: "sms",
      title: I18n.t("admin.sms_preview"),
      body,
    };
  }
  if (testKey === "wa_order") {
    return {
      kind: "wa",
      title: I18n.t("admin.whatsapp_preview"),
      src: ENGAGEMENT_WA_PREVIEW_ORDER,
    };
  }
  if (testKey === "wa_fulfil") {
    return {
      kind: "wa",
      title: I18n.t("admin.whatsapp_preview"),
      src: ENGAGEMENT_WA_PREVIEW_FULFIL,
    };
  }
  if (testKey === "wa_ac") {
    const discountOn =
      setting?.selectedDiscount === "1" ||
      setting?.acWhatsappDiscoutEnabled === true ||
      setting?.ac_whatsapp_discout_enabled === true;
    return {
      kind: "wa",
      title: I18n.t("admin.whatsapp_preview"),
      src: discountOn
        ? ENGAGEMENT_WA_PREVIEW_ABANDON_DISCOUNT
        : ENGAGEMENT_WA_PREVIEW_ABANDON,
    };
  }
  if (testKey === "wa_cod") {
    return {
      kind: "wa",
      title: I18n.t("admin.whatsapp_preview"),
      src: ENGAGEMENT_WA_PREVIEW_COD,
    };
  }
  return null;
}

function EngagementRows({ flags, testLoading, onTest, setting }) {
  const [previewModel, setPreviewModel] = useState(null);

  const rows = [];

  if (flags.smsConfirmation) {
    rows.push({
      id: "sms_order",
      label: I18n.t("custom_setup.engagement_order_placed_sms"),
      channel: "SMS",
      testKey: "sms_order",
    });
  }
  if (flags.smsFulfilment) {
    rows.push({
      id: "sms_fulfil",
      label: I18n.t("custom_setup.engagement_fulfilment_sms"),
      channel: "SMS",
      testKey: "sms_fulfil",
    });
  }
  if (flags.smsAbandoned) {
    rows.push({
      id: "sms_ac",
      label: I18n.t("custom_setup.engagement_abandoned_sms"),
      channel: "SMS",
      testKey: "sms_ac",
    });
  }
  if (flags.waConfirmation) {
    rows.push({
      id: "wa_order",
      label: I18n.t("custom_setup.engagement_order_placed_wa"),
      channel: "WhatsApp",
      testKey: "wa_order",
    });
  }
  if (flags.waFulfilment) {
    rows.push({
      id: "wa_fulfil",
      label: I18n.t("custom_setup.engagement_fulfilment_wa"),
      channel: "WhatsApp",
      testKey: "wa_fulfil",
    });
  }
  if (flags.waAbandoned) {
    rows.push({
      id: "wa_ac",
      label: I18n.t("custom_setup.engagement_abandoned_wa"),
      channel: "WhatsApp",
      testKey: "wa_ac",
    });
  }
  if (flags.waCodVerification) {
    rows.push({
      id: "wa_cod",
      label: I18n.t("custom_setup.engagement_cod_verification_wa"),
      channel: "WhatsApp",
      testKey: "wa_cod",
    });
  }

  const manageSmsKey = (testKey) => SMS_TEMPLATE_PARAM_BY_TEST_KEY[testKey];

  return (
    <BlockStack gap="300">
      <Text as="p" variant="bodySm" tone="subdued">
        {I18n.t("custom_setup.engagement_intro")}
      </Text>
      <BlockStack gap="200">
        {rows.map((row) => (
          <Card key={row.id} padding="300">
            <InlineGrid
              columns={{ xs: "1fr", sm: "1fr auto" }}
              gap="300"
              alignItems="center"
            >
              <BlockStack gap="050">
                <Text as="span" variant="bodyMd" fontWeight="semibold">
                  {row.label}
                </Text>
                <Text as="span" variant="bodySm" tone="subdued">
                  {row.channel}
                </Text>
              </BlockStack>
              <InlineStack gap="200" blockAlign="center" wrap>
                <Button
                  size="slim"
                  variant="secondary"
                  onClick={() =>
                    setPreviewModel(
                      buildEngagementPreviewModel(row.testKey, setting),
                    )
                  }
                >
                  {I18n.t("custom_setup.engagement_preview")}
                </Button>
                {manageSmsKey(row.testKey) ? (
                  <Button
                    variant="plain"
                    onClick={() => {
                      let path = "/custom_setup";
                      try {
                        const p = (window.location.pathname || "")
                          .replace(/\/+$/, "") || "";
                        const sanitized = safeInternalPath(p || "/custom_setup");
                        if (sanitized) path = sanitized;
                      } catch (_) {}
                      navigateToPreservingParams("/features/notifications", {
                        smsTemplate: manageSmsKey(row.testKey),
                        returnTo: path,
                      });
                    }}
                  >
                    {I18n.t("custom_setup.engagement_manage_sms_template")}
                  </Button>
                ) : null}
                <Button
                  size="slim"
                  loading={testLoading === row.testKey}
                  disabled={
                    testLoading != null && testLoading !== row.testKey
                  }
                  onClick={() => onTest(row.testKey)}
                >
                  {I18n.t("custom_setup.test")}
                </Button>
              </InlineStack>
            </InlineGrid>
          </Card>
        ))}
      </BlockStack>
      <Modal
        open={Boolean(previewModel)}
        onClose={() => setPreviewModel(null)}
        title={previewModel?.title || ""}
        primaryAction={{
          content: I18n.t("admin.close"),
          onAction: () => setPreviewModel(null),
        }}
      >
        <Modal.Section>
          {previewModel?.kind === "sms" ? (
            <TextField
              label={I18n.t("admin.sms_preview")}
              multiline={6}
              value={previewModel.body}
              readOnly
              autoComplete="off"
            />
          ) : null}
          {previewModel?.kind === "wa" && previewModel.src ? (
            <Box paddingBlockEnd="200">
              <img
                src={previewModel.src}
                alt=""
                style={{
                  maxWidth: "100%",
                  borderRadius: "8px",
                  display: "block",
                  marginInline: "auto",
                }}
              />
            </Box>
          ) : null}
        </Modal.Section>
      </Modal>
    </BlockStack>
  );
}

const CUSTOM_SETUP_PATH = "/custom_setup";

function PartialRulesTable({ shopify, onContinue }) {
  const [rules, setRules] = useState([]);
  const [loading, setLoading] = useState(true);
  const [reorderLoading, setReorderLoading] = useState(false);

  const fetchRuleSets = useCallback(() => {
    return Api.get("/partial_rule_sets")
      .then((res) => {
        setRules(Array.isArray(res.data) ? res.data : []);
      })
      .catch(() => setRules([]));
  }, []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetchRuleSets().finally(() => {
      if (!cancelled) setLoading(false);
    });
    return () => {
      cancelled = true;
    };
  }, [fetchRuleSets]);

  const handleMoveUp = useCallback(
    (rule) => {
      const idx = rules.findIndex((r) => r.id === rule.id);
      if (idx <= 0) return;
      const newOrder = [...rules];
      [newOrder[idx - 1], newOrder[idx]] = [newOrder[idx], newOrder[idx - 1]];
      setReorderLoading(true);
      Api.post("/partial_rule_sets/reorder", {
        ruleIds: newOrder.map((r) => r.id),
      })
        .then((resp) => {
          setRules(Array.isArray(resp.data) ? resp.data : newOrder);
          shopify?.toast?.show(I18n.t("partial.reorder_success"));
        })
        .catch(() => {
          shopify?.toast?.show(I18n.t("partial.reorder_error"), { isError: true });
        })
        .finally(() => setReorderLoading(false));
    },
    [rules, shopify],
  );

  const handleMoveDown = useCallback(
    (rule) => {
      const idx = rules.findIndex((r) => r.id === rule.id);
      if (idx < 0 || idx >= rules.length - 1) return;
      const newOrder = [...rules];
      [newOrder[idx], newOrder[idx + 1]] = [newOrder[idx + 1], newOrder[idx]];
      setReorderLoading(true);
      Api.post("/partial_rule_sets/reorder", {
        ruleIds: newOrder.map((r) => r.id),
      })
        .then((resp) => {
          setRules(Array.isArray(resp.data) ? resp.data : newOrder);
          shopify?.toast?.show(I18n.t("partial.reorder_success"));
        })
        .catch(() => {
          shopify?.toast?.show(I18n.t("partial.reorder_error"), { isError: true });
        })
        .finally(() => setReorderLoading(false));
    },
    [rules, shopify],
  );

  const openEdit = useCallback((rule) => {
    try {
      sessionStorage.setItem(PARTIAL_RULE_EDIT_PAYLOAD_KEY, JSON.stringify(rule));
    } catch (_) {}
    setPartialPaymentReturnPath(CUSTOM_SETUP_PATH);
    navigateTo("/features/partial-payment/edit");
  }, []);

  const openAddRule = useCallback(() => {
    setPartialPaymentReturnPath(CUSTOM_SETUP_PATH);
    navigateTo("/features/partial-payment/add");
  }, []);

  const handleDelete = useCallback(
    (id) => {
      Api.delete(`/partial_rule_sets/${id}`)
        .then(() => {
          shopify?.toast?.show(I18n.t("partial.delete_success"));
          return fetchRuleSets();
        })
        .catch(() => {
          shopify?.toast?.show(I18n.t("partial.delete_error"), { isError: true });
        });
    },
    [fetchRuleSets, shopify],
  );

  if (loading) {
    return (
      <Text as="p" tone="subdued">
        {I18n.t("custom_setup.loading_rules")}
      </Text>
    );
  }

  if (!rules.length) {
    return (
      <BlockStack gap="300">
        <Banner tone="warning">
          <p>{I18n.t("custom_setup.no_rules_yet")}</p>
        </Banner>
        <InlineStack gap="200" wrap align="start">
          <Button icon={PlusMinor} onClick={openAddRule}>
            {I18n.t("partial.add_rule")}
          </Button>
          {onContinue ? (
            <Button variant="primary" onClick={onContinue}>
              {I18n.t("custom_setup.continue_next_section")}
            </Button>
          ) : null}
        </InlineStack>
      </BlockStack>
    );
  }

  const tableRows = rules.map((rule) => {
    const amount = rule.amount === null || rule.amount === undefined ? 0 : rule.amount;
    const isNullAmount = rule.amount === null || rule.amount === undefined;
    let amountTypeDisplay;
    if (isNullAmount) {
      amountTypeDisplay = "";
    } else if (rule.amountType === "cod" || rule.amountType === "fixed") {
      amountTypeDisplay = I18n.t("partial.amount_type_fixed");
    } else {
      amountTypeDisplay = I18n.t("partial.amount_type_percentage");
    }
    const paymentText = isNullAmount ? `${amount}` : `${amount} (${amountTypeDisplay})`;
    const ruleIndex = rules.findIndex((r) => r.id === rule.id);
    const canMoveUp = ruleIndex > 0;
    const canMoveDown = ruleIndex >= 0 && ruleIndex < rules.length - 1;

    return [
      <InlineStack key={`order-${rule.id}`} gap="100" blockAlign="center">
        <Button
          size="micro"
          icon={ChevronUpMinor}
          onClick={() => handleMoveUp(rule)}
          disabled={!canMoveUp || reorderLoading}
          accessibilityLabel={I18n.t("partial.move_up")}
        />
        <Button
          size="micro"
          icon={ChevronDownMinor}
          onClick={() => handleMoveDown(rule)}
          disabled={!canMoveDown || reorderLoading}
          accessibilityLabel={I18n.t("partial.move_down")}
        />
      </InlineStack>,
      <Text key={`name-${rule.id}`} as="span" variant="bodyMd">
        {rule.ruleName}
      </Text>,
      paymentText,
      <InlineStack key={`actions-${rule.id}`} gap="200">
        <Button
          size="micro"
          icon={EditMinor}
          onClick={() => openEdit(rule)}
          accessibilityLabel={I18n.t("partial.edit_rule")}
        />
        <Button
          size="micro"
          icon={DeleteMinor}
          onClick={() => handleDelete(rule.id)}
          tone="critical"
          accessibilityLabel={I18n.t("partial.delete_rule")}
        />
      </InlineStack>,
    ];
  });

  return (
    <BlockStack gap="400">
      <DataTable
        columnContentTypes={["text", "text", "text", "text"]}
        headings={[
          I18n.t("partial.order"),
          I18n.t("partial.rule_name"),
          I18n.t("partial.payment_amount"),
          I18n.t("admin.actions"),
        ]}
        rows={tableRows}
      />
      <InlineStack gap="200" wrap align="start">
        <Button icon={PlusMinor} onClick={openAddRule}>
          {I18n.t("partial.add_rule")}
        </Button>
        {onContinue ? (
          <Button variant="primary" onClick={onContinue}>
            {I18n.t("custom_setup.continue_next_section")}
          </Button>
        ) : null}
      </InlineStack>
    </BlockStack>
  );
}

export default function CustomSetup() {
  const shopify = useAppBridge();
  const {
    setting: [setting, setSetting],
    shop: [shop, setShop],
    plan: [plan],
  } = useContext(StoreContext);

  const isPaidPlan = useMemo(
    () => {
      const planName = String(plan?.name || "").toLowerCase();
      if (!planName) return false;
      return planName !== "free" && !hasNoChargeId(shop);
    },
    [plan?.name, shop],
  );

  const isEnterprisePlus = plan?.name === "Enterprise Plus";

  const goToSubscription = useCallback((e) => {
    if (e) e.preventDefault();
    navigateTo("/subscription");
  }, []);

  const codFormOn = useCodFormOn();
  const sections = useMemo(
    () => getCustomSetupSections(setting, { codFormOn }),
    [setting, codFormOn],
  );

  /** Same pattern as PreOrderSetting: POST full merged setting so Rails validations pass. */
  const buildFullSettingPayload = useCallback(
    (patch) => {
      const base =
        setting && typeof setting === "object" ? { ...setting } : {};
      delete base.setting;
      return { ...base, ...patch };
    },
    [setting],
  );

  const prevSectionKeyRef = useRef("");
  const [openMap, setOpenMap] = useState({});
  const [savingPopup, setSavingPopup] = useState(false);
  const [savingPrefilled, setSavingPrefilled] = useState(false);
  const [engagementBanner, setEngagementBanner] = useState(null);
  const [testLoading, setTestLoading] = useState(null);
  const [ownerPhoneModalOpen, setOwnerPhoneModalOpen] = useState(false);
  const [ownerPhoneDraft, setOwnerPhoneDraft] = useState("");
  const [savingOwnerPhone, setSavingOwnerPhone] = useState(false);
  const [ownerPhoneModalError, setOwnerPhoneModalError] = useState("");

  const [popupDraft, setPopupDraft] = useState({
    prePrimaryButtonColor:
      setting?.prePrimaryButtonColor || setting?.pre_primary_button_color || "#666666",
    brandLogoUrl: setting?.brandLogoUrl || setting?.brand_logo_url || "",
    preShowBranding:
      setting?.preShowBranding ?? setting?.pre_show_branding ?? true,
  });

  const [preOrderDraft, setPreOrderDraft] = useState({
    countryCodeList:
      setting?.countryCodeList ?? setting?.country_code_list ?? "",
    isPrefilledAddressEnabled: Boolean(
      setting?.isPrefilledAddressEnabled ?? setting?.is_prefilled_address_enabled,
    ),
    persistentSignin: Boolean(
      setting?.persistentSignin ?? setting?.persistent_signin,
    ),
  });
  const [otpCountrySearch, setOtpCountrySearch] = useState("");
  const [otpCountryPopoverActive, setOtpCountryPopoverActive] = useState(false);

  useEffect(() => {
    setPopupDraft({
      prePrimaryButtonColor:
        setting?.prePrimaryButtonColor || setting?.pre_primary_button_color || "#666666",
      brandLogoUrl: setting?.brandLogoUrl || setting?.brand_logo_url || "",
      preShowBranding:
        setting?.preShowBranding ?? setting?.pre_show_branding ?? true,
    });
  }, [
    setting?.prePrimaryButtonColor,
    setting?.pre_primary_button_color,
    setting?.brandLogoUrl,
    setting?.brand_logo_url,
    setting?.preShowBranding,
    setting?.pre_show_branding,
  ]);

  useEffect(() => {
    setPreOrderDraft({
      countryCodeList:
        setting?.countryCodeList ?? setting?.country_code_list ?? "",
      isPrefilledAddressEnabled: Boolean(
        setting?.isPrefilledAddressEnabled ?? setting?.is_prefilled_address_enabled,
      ),
      persistentSignin: Boolean(
        setting?.persistentSignin ?? setting?.persistent_signin,
      ),
    });
  }, [
    setting?.countryCodeList,
    setting?.country_code_list,
    setting?.isPrefilledAddressEnabled,
    setting?.is_prefilled_address_enabled,
    setting?.persistentSignin,
    setting?.persistent_signin,
  ]);

  const filteredOtpCountries = useMemo(
    () =>
      countryOptions.filter((c) =>
        c.label.toLowerCase().includes(otpCountrySearch.toLowerCase()),
      ),
    [otpCountrySearch],
  );

  const toggleOtpCountryPopover = useCallback(
    () => setOtpCountryPopoverActive((a) => !a),
    [],
  );

  const isOnlyIndiaSelectedForOtp = useMemo(() => {
    const raw = (preOrderDraft.countryCodeList || "").trim();
    if (!raw) return false;
    const codes = raw.split(",").map((c) => c.trim().toUpperCase());
    return codes.length === 1 && codes[0] === "IN";
  }, [preOrderDraft.countryCodeList]);

  useEffect(() => {
    const key = sections.map((s) => s.id).join("|");
    if (!sections.length) {
      prevSectionKeyRef.current = "";
      return;
    }
    if (key === prevSectionKeyRef.current) return;
    prevSectionKeyRef.current = key;
    const next = {};
    sections.forEach((s, i) => {
      next[s.id] = i === 0;
    });
    setOpenMap(next);
  }, [sections]);

  /** Accordion: only one section open; clicking the open header closes it. */
  const toggleSection = useCallback(
    (id) => {
      setOpenMap((prev) => {
        if (prev[id]) return { ...prev, [id]: false };
        const next = {};
        sections.forEach((s) => {
          next[s.id] = s.id === id;
        });
        return next;
      });
    },
    [sections],
  );

  /** After a successful save, collapse this step and expand the next (if any). */
  const advanceToNextSection = useCallback(
    (completedSectionId) => {
      const idx = sections.findIndex((s) => s.id === completedSectionId);
      if (idx < 0) return;
      const nextSection = sections[idx + 1];
      setOpenMap(() => {
        const map = {};
        sections.forEach((s) => {
          map[s.id] = Boolean(nextSection && s.id === nextSection.id);
        });
        return map;
      });
    },
    [sections],
  );

  const savePopupBranding = useCallback(async () => {
    setSavingPopup(true);
    try {
      const patch = {
        ...brandColorPatch(popupDraft.prePrimaryButtonColor),
        brandLogoUrl: popupDraft.brandLogoUrl?.trim(),
      };
      if (isEnterprisePlus) {
        patch.preShowBranding = popupDraft.preShowBranding;
      }
      const response = await Api.post("/settings", {
        setting: buildFullSettingPayload(patch),
      });
      setSetting(response.data);
      shopify?.toast?.show(I18n.t("custom_setup.save_success"));
      advanceToNextSection("popup");
    } catch (e) {
      console.error(e);
      shopify?.toast?.show(I18n.t("custom_setup.save_error"), { isError: true });
    } finally {
      setSavingPopup(false);
    }
  }, [
    advanceToNextSection,
    buildFullSettingPayload,
    isEnterprisePlus,
    popupDraft,
    setSetting,
    shopify,
  ]);

  const previewSetting = useMemo(
    () => ({
      ...setting,
      ...popupDraft,
      ...brandColorPatch(popupDraft.prePrimaryButtonColor),
      isPrefilledAddressEnabled: preOrderDraft.isPrefilledAddressEnabled,
    }),
    [setting, popupDraft, preOrderDraft.isPrefilledAddressEnabled],
  );

  const savePreOrderOtpSection = useCallback(async () => {
    const list = (preOrderDraft.countryCodeList || "").trim();
    if (!list) {
      shopify?.toast?.show(I18n.t("pre_order.must_select_country"), {
        isError: true,
      });
      return;
    }
    setSavingPrefilled(true);
    try {
      const patch = { countryCodeList: list };
      if (isPaidPlan) {
        patch.isPrefilledAddressEnabled = preOrderDraft.isPrefilledAddressEnabled;
      }
      // Persistent sign-in is available on every plan, Free included.
      patch.persistentSignin = preOrderDraft.persistentSignin;
      const response = await Api.post("/settings", {
        setting: buildFullSettingPayload(patch),
      });
      setSetting(response.data);
      shopify?.toast?.show(I18n.t("custom_setup.save_success"));
      advanceToNextSection("pre_order_otp");
    } catch (e) {
      console.error(e);
      shopify?.toast?.show(I18n.t("custom_setup.save_error"), { isError: true });
    } finally {
      setSavingPrefilled(false);
    }
  }, [
    advanceToNextSection,
    buildFullSettingPayload,
    preOrderDraft,
    setSetting,
    shopify,
    isPaidPlan,
  ]);

  const openOwnerPhoneModal = useCallback(() => {
    const current = shop?.ownerPhone ?? shop?.owner_phone ?? "";
    setOwnerPhoneDraft(String(current));
    setOwnerPhoneModalError("");
    setOwnerPhoneModalOpen(true);
  }, [shop?.ownerPhone, shop?.owner_phone]);

  const saveOwnerPhone = useCallback(async () => {
    if (!shop?.id) return;
    setSavingOwnerPhone(true);
    setOwnerPhoneModalError("");
    try {
      const res = await Api.post("/settings/update_owner_phone", {
        shop_id: shop.id,
        owner_phone: ownerPhoneDraft.trim(),
      });
      if (res.data?.success) {
        const stored = res.data.ownerPhone ?? res.data.owner_phone;
        const sentTo = res.data.number || stored;
        setShop((prev) =>
          prev
            ? { ...prev, owner_phone: stored, ownerPhone: stored }
            : prev,
        );
        setEngagementBanner((prev) =>
          prev && prev.tone === "success"
            ? {
                ...prev,
                sentToNumber: sentTo,
                message: I18n.t("custom_setup.engagement_test_sent_body", {
                  number: sentTo || "",
                }),
              }
            : prev,
        );
        shopify?.toast?.show(I18n.t("custom_setup.engagement_phone_saved"));
        setOwnerPhoneModalOpen(false);
      } else {
        throw new Error("Save failed");
      }
    } catch (e) {
      const err =
        e.response?.data?.error ||
        I18n.t("custom_setup.engagement_phone_save_failed");
      setOwnerPhoneModalError(
        typeof err === "string" ? err : I18n.t("custom_setup.engagement_phone_save_failed"),
      );
    } finally {
      setSavingOwnerPhone(false);
    }
  }, [ownerPhoneDraft, setShop, shop?.id, shopify]);

  const handleEngagementTest = useCallback(
    (rowKey) => {
      const spec = ENGAGEMENT_TEST_TYPES[rowKey];
      if (!spec || !shop?.id) return;
      setTestLoading(rowKey);
      setEngagementBanner(null);
      Api.post("/settings/test_notification", {
        type: spec.type,
        mode: spec.mode,
        shop_id: shop.id,
      })
        .then((res) => {
          if (res.data.success) {
            const sentTo = res.data.number || "";
            const body = I18n.t("custom_setup.engagement_test_sent_body", {
              number: sentTo,
            });
            if (spec.mode === "sms") {
              setEngagementBanner({
                tone: "success",
                title: I18n.t("admin.test_sms_success"),
                message: body,
                sentToNumber: sentTo,
                mode: "sms",
              });
            } else {
              setEngagementBanner({
                tone: "success",
                title: I18n.t("admin.test_whatsapp_success"),
                message: body,
                sentToNumber: sentTo,
                mode: "whatsapp",
              });
            }
          } else {
            throw new Error("Test failed");
          }
        })
        .catch((error) => {
          const errText =
            error.response?.data?.error || I18n.t("admin.something_went_wrong");
          if (spec.mode === "sms") {
            setEngagementBanner({
              tone: "critical",
              title: I18n.t("admin.test_sms_failed"),
              message: errText,
            });
          } else {
            setEngagementBanner({
              tone: "critical",
              title: I18n.t("admin.test_whatsapp_failed"),
              message: errText,
            });
          }
          shopify?.toast?.show(errText, { isError: true });
        })
        .finally(() => setTestLoading(null));
    },
    [shop?.id, shopify],
  );

  const finishToDashboard = useCallback(() => {
    clearCustomSetupPending();
    navigateTo("/");
  }, []);

  if (!sections.length) {
    return (
      <BlockStack gap="400">
        <Text as="h1" variant="headingLg">
          {I18n.t("custom_setup.page_title")}
        </Text>
        <Banner tone="info">
          <p>{I18n.t("custom_setup.empty_state")}</p>
        </Banner>
        <InlineStack align="start">
          <Button variant="primary" onClick={finishToDashboard}>
            {I18n.t("custom_setup.go_dashboard")}
          </Button>
        </InlineStack>
      </BlockStack>
    );
  }

  return (
    <BlockStack gap="500">
      <BlockStack gap="200">
        <Text as="h1" variant="headingLg">
          {I18n.t("custom_setup.page_title")}
        </Text>
        <Text as="p" tone="subdued">
          {I18n.t("custom_setup.page_subtitle")}
        </Text>
      </BlockStack>

      <Modal
        open={ownerPhoneModalOpen}
        onClose={() => setOwnerPhoneModalOpen(false)}
        title={I18n.t("custom_setup.engagement_update_phone_title")}
        primaryAction={{
          content: I18n.t("custom_setup.engagement_save_phone"),
          onAction: saveOwnerPhone,
          loading: savingOwnerPhone,
        }}
        secondaryActions={[
          {
            content: I18n.t("admin.cancel"),
            onAction: () => setOwnerPhoneModalOpen(false),
            disabled: savingOwnerPhone,
          },
        ]}
      >
        <Modal.Section>
          <FormLayout>
            {ownerPhoneModalError ? (
              <Banner tone="critical" onDismiss={() => setOwnerPhoneModalError("")}>
                <p>{ownerPhoneModalError}</p>
              </Banner>
            ) : null}
            <TextField
              label={I18n.t("custom_setup.engagement_owner_phone_label")}
              value={ownerPhoneDraft}
              onChange={setOwnerPhoneDraft}
              type="tel"
              autoComplete="tel"
              helpText={I18n.t("custom_setup.engagement_owner_phone_help")}
            />
          </FormLayout>
        </Modal.Section>
      </Modal>

      <BlockStack gap="300">
        {sections.map((section) => {
          const open = Boolean(openMap[section.id]);
          return (
            <Card key={section.id} padding="0">
              <SectionHeader
                open={open}
                title={I18n.t(section.titleKey)}
                subtitle={I18n.t(section.subtitleKey)}
                onToggle={() => toggleSection(section.id)}
              />
              <Collapsible id={section.id} open={open}>
                <Box padding="400" paddingBlockStart="0">
                  <Divider />
                  <Box paddingBlockStart="400">
                    {section.id === "popup" ? (
                      <BlockStack gap="500">
                        <InlineGrid columns={{ xs: "1fr", md: "minmax(0,1fr) minmax(300px,380px)" }} gap="500">
                          <BlockStack gap="400">
                            <Text as="h3" variant="headingSm">
                              {I18n.t("custom_setup.popup_subheading")}
                            </Text>
                            <BlockStack gap="100">
                              <HexColorPicker
                                color={popupDraft.prePrimaryButtonColor}
                                label={I18n.t("custom_setup.brand_color")}
                                onChange={(v) =>
                                  setPopupDraft((d) => ({
                                    ...d,
                                    prePrimaryButtonColor: v,
                                  }))
                                }
                              />
                              <Text as="p" variant="bodySm" tone="subdued">
                                {I18n.t("custom_setup.brand_color_help")}
                              </Text>
                            </BlockStack>
                            <TextField
                              label={I18n.t("custom_setup.logo_url")}
                              value={popupDraft.brandLogoUrl}
                              onChange={(v) =>
                                setPopupDraft((d) => ({ ...d, brandLogoUrl: v }))
                              }
                              autoComplete="off"
                            />
                            <BlockStack gap="300">
                              <Checkbox
                                label={I18n.t("pre_order.show_cod_king_branding")}
                                helpText={
                                  isEnterprisePlus
                                    ? I18n.t(
                                        "pre_order.show_cod_king_branding_help",
                                      )
                                    : undefined
                                }
                                checked={
                                  popupDraft.preShowBranding === true ||
                                  popupDraft.preShowBranding === "true"
                                }
                                onChange={(v) =>
                                  setPopupDraft((d) => ({
                                    ...d,
                                    preShowBranding: v,
                                  }))
                                }
                                disabled={!isEnterprisePlus}
                              />
                              {!isEnterprisePlus && (
                                <Text as="p" variant="bodyMd" tone="subdued">
                                  {I18n.t(
                                    "pre_order.show_branding_enterprise_plus_only",
                                  )}{" "}
                                  <Link url="/subscription" onClick={goToSubscription}>
                                    {I18n.t("pre_order.upgrade_to_hide_branding")}
                                  </Link>
                                </Text>
                              )}
                            </BlockStack>
                            <InlineStack align="start">
                              <Button
                                variant="primary"
                                loading={savingPopup}
                                onClick={savePopupBranding}
                              >
                                {I18n.t("custom_setup.save_popup")}
                              </Button>
                            </InlineStack>
                          </BlockStack>
                          <WidgetPreviewPanel setting={previewSetting} showTabs={false} />
                        </InlineGrid>
                        <PopupProductPreview shop={shop} setting={setting} />
                      </BlockStack>
                    ) : null}

                    {section.id === "pre_order_otp" ? (
                      <BlockStack gap="400">
                        <Text as="p" variant="bodySm" tone="subdued">
                          {I18n.t("custom_setup.pre_order_body")}
                        </Text>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodySm" fontWeight="semibold">
                            {I18n.t("pre_order.select_countries")}
                          </Text>
                          {preOrderDraft.countryCodeList ? (
                            <Box>
                              <Tag>{preOrderDraft.countryCodeList}</Tag>
                            </Box>
                          ) : (
                            <Banner tone="warning">
                              <p>{I18n.t("pre_order.must_select_country")}</p>
                            </Banner>
                          )}
                          <InlineStack gap="200" blockAlign="center" wrap>
                            <Popover
                              active={otpCountryPopoverActive}
                              activator={
                                <Button
                                  onClick={toggleOtpCountryPopover}
                                  disclosure
                                >
                                  {I18n.t("pre_order.select_countries_button")}
                                </Button>
                              }
                              onClose={toggleOtpCountryPopover}
                            >
                              <Popover.Pane fixed>
                                <Box padding="200">
                                  <TextField
                                    placeholder={I18n.t(
                                      "pre_order.search_country",
                                    )}
                                    value={otpCountrySearch}
                                    onChange={setOtpCountrySearch}
                                    clearButton
                                    onClearButtonClick={() =>
                                      setOtpCountrySearch("")
                                    }
                                  />
                                  <Box
                                    style={{
                                      maxHeight: "400px",
                                      overflowY: "auto",
                                      overflowX: "hidden",
                                    }}
                                  >
                                    <OptionList
                                      title={I18n.t("pre_order.select_countries")}
                                      onChange={(value) =>
                                        setPreOrderDraft((d) => ({
                                          ...d,
                                          countryCodeList: Array.isArray(value)
                                            ? value.join(",")
                                            : value,
                                        }))
                                      }
                                      options={filteredOtpCountries}
                                      selected={
                                        preOrderDraft.countryCodeList
                                          ? preOrderDraft.countryCodeList.split(
                                              ",",
                                            )
                                          : []
                                      }
                                      allowMultiple
                                    />
                                  </Box>
                                </Box>
                              </Popover.Pane>
                            </Popover>
                          </InlineStack>
                          <Text as="p" variant="bodySm" tone="subdued">
                            {I18n.t("pre_order.select_countries_required")}
                          </Text>
                        </BlockStack>
                        {preOrderDraft.countryCodeList?.trim() &&
                        !isOnlyIndiaSelectedForOtp ? (
                          <Text as="p" variant="bodySm" tone="subdued">
                            {I18n.t("custom_setup.prefilled_india_only_notice")}
                          </Text>
                        ) : null}
                        {isOnlyIndiaSelectedForOtp ? (
                          <BlockStack gap="200">
                            <Checkbox
                              label={I18n.t("custom_setup.prefilled_address")}
                              checked={preOrderDraft.isPrefilledAddressEnabled}
                              helpText={I18n.t("pre_order.prefilled_help")}
                              disabled={!isPaidPlan}
                              onChange={(checked) =>
                                setPreOrderDraft((d) => ({
                                  ...d,
                                  isPrefilledAddressEnabled: checked,
                                }))
                              }
                            />
                            {!isPaidPlan ? (
                              <Text as="p" variant="bodySm" tone="subdued">
                                {I18n.t("custom_setup.prefilled_paid_plan_notice")}{" "}
                                <Link
                                  url="/subscription"
                                  onClick={goToSubscription}
                                >
                                  {I18n.t("custom_setup.prefilled_upgrade_now")}
                                </Link>
                              </Text>
                            ) : null}
                          </BlockStack>
                        ) : null}
                        <BlockStack gap="200">
                          <Checkbox
                            label={I18n.t("pre_order.persistent_signin_label")}
                            helpText={I18n.t("pre_order.persistent_signin_help")}
                            checked={
                              preOrderDraft.persistentSignin === true ||
                              preOrderDraft.persistentSignin === "true"
                            }
                            onChange={(checked) =>
                              setPreOrderDraft((d) => ({
                                ...d,
                                persistentSignin: checked,
                              }))
                            }
                          />
                        </BlockStack>
                        <InlineStack align="start">
                          <Button
                            variant="primary"
                            loading={savingPrefilled}
                            onClick={savePreOrderOtpSection}
                          >
                            {I18n.t("custom_setup.save_prefilled")}
                          </Button>
                        </InlineStack>
                      </BlockStack>
                    ) : null}

                    {section.id === "partial_payment" ? (
                      <PartialRulesTable
                        shopify={shopify}
                        onContinue={() => advanceToNextSection("partial_payment")}
                      />
                    ) : null}

                    {section.id === "cod_form" ? (
                      <CustomSetupCodForm
                        onContinue={() => advanceToNextSection("cod_form")}
                      />
                    ) : null}

                    {section.id === "engagement" ? (
                      <BlockStack gap="400">
                        {engagementBanner ? (
                          <Banner
                            tone={engagementBanner.tone}
                            title={engagementBanner.title}
                            onDismiss={() => setEngagementBanner(null)}
                          >
                            <BlockStack gap="300">
                              <Text as="p" variant="bodyMd">
                                {engagementBanner.message}
                              </Text>
                              {engagementBanner.tone === "success" ? (
                                <InlineStack gap="200" wrap blockAlign="center">
                                  <Button onClick={openOwnerPhoneModal}>
                                    {I18n.t("custom_setup.engagement_change_number")}
                                  </Button>
                                  <Button onClick={openCrispSupportChat}>
                                    {I18n.t("custom_setup.engagement_chat_support")}
                                  </Button>
                                </InlineStack>
                              ) : null}
                            </BlockStack>
                          </Banner>
                        ) : null}
                        <EngagementRows
                          flags={section.flags}
                          testLoading={testLoading}
                          onTest={handleEngagementTest}
                          setting={setting}
                        />
                      </BlockStack>
                    ) : null}
                  </Box>
                </Box>
              </Collapsible>
            </Card>
          );
        })}
      </BlockStack>

      <Card>
        <Box padding="400">
          <InlineStack align="end" blockAlign="center" wrap>
            <Button variant="primary" onClick={finishToDashboard}>
              {I18n.t("custom_setup.finish_dashboard")}
            </Button>
          </InlineStack>
        </Box>
      </Card>
    </BlockStack>
  );
}
