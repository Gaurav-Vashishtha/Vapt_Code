import React, {
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import {
  Badge,
  Banner,
  BlockStack,
  Box,
  Button,
  Card,
  Checkbox,
  ChoiceList,
  Divider,
  FormLayout,
  Icon,
  InlineStack,
  Link,
  Select,
  Text,
  TextField,
} from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import HexColorPicker from "../HexColorPicker";
import LiveWidgetPreview from "../WidgetPreview/LiveWidgetPreview";
import UiCustomizationModal from "./UiCustomizationModal";
import {
  SectionCard,
  SettingGroup,
  SettingRow,
} from "../SettingsPrimitives";
import { navigateTo } from "../../../utils/navigate";
import { hasNoChargeId } from "../../utils/shopUtils";
import {
  CartIcon,
  ChatIcon,
  CheckCircleIcon,
  CodeIcon,
  CreditCardIcon,
  DiscountIcon,
  HideIcon,
  HomeIcon,
  MobileIcon,
  PaintBrushFlatIcon,
} from "../../Pages/SettingsHub/icons";
import {
  UI_TEXT_GROUPS,
  UI_VISIBILITY_PAGE_TYPES,
  UI_DEFAULT_BRAND_COLOR,
  MAX_VISIBILITY_PATHS,
  normalizeUiCustomization,
  normalizeVisibilityPath,
  buildBulkTexts,
  parseBulkTexts,
} from "../uiCustomizationCatalog";


// Rail sections. Labels resolve at render because the locale is set once the
// shop's setting loads, after this module is imported.
// Rail sections. Anything the widget shows on more than one step is its own
// section rather than being filed under whichever screen it happened to be
// noticed on; the screen sections then hold only what is genuinely theirs.
//
// `section` matches UI_TEXT_GROUPS[].section, so a section's copy fields are
// just the groups filed under it. `screen` is the index into the settings
// controls in renderScreenFields, and only the screen sections have one.
const UI_SECTIONS = [
  {
    id: "branding",
    group: "Shared",
    get label() {
      return I18n.t("ui_customization_editor.logo_and_colours");
    },
    icon: PaintBrushFlatIcon,
    section: "branding",
    previewScreen: "phone",
  },
  {
    id: "order_summary",
    group: "Shared",
    get label() {
      return I18n.t("ui_customization_editor.order_summary");
    },
    icon: CartIcon,
    section: "order_summary",
    previewScreen: "order-summary",
  },
  {
    id: "address",
    group: "Shared",
    get label() {
      return I18n.t("ui_customization_editor.delivery_address");
    },
    icon: HomeIcon,
    section: "address",
    previewScreen: "address",
  },
  {
    id: "coupons",
    group: "Shared",
    get label() {
      return I18n.t("ui_customization_editor.coupons");
    },
    icon: DiscountIcon,
    section: "coupons",
    previewScreen: "coupons",
  },
  {
    id: "messages",
    group: "Shared",
    get label() {
      return I18n.t("ui_customization_editor.pop_up_messages");
    },
    icon: ChatIcon,
    section: "messages",
    previewScreen: "dialogs",
  },
  {
    id: "login",
    groupKey: "pre_order.customization_group_screens",
    get label() {
      return I18n.t("ui_customization_editor.phone_number_screen");
    },
    icon: MobileIcon,
    screen: 0,
    section: "login",
    previewScreen: "phone",
  },
  {
    id: "verification",
    groupKey: "pre_order.customization_group_screens",
    get label() {
      return I18n.t("ui_customization_editor.verify_code_screen");
    },
    icon: CheckCircleIcon,
    screen: 1,
    section: "verification",
    previewScreen: "otp",
  },
  {
    id: "payments",
    groupKey: "pre_order.customization_group_screens",
    get label() {
      return I18n.t("ui_customization_editor.payment_screen");
    },
    icon: CreditCardIcon,
    screen: 2,
    section: "payments",
    previewScreen: "payment",
  },
  {
    id: "visibility",
    groupKey: "pre_order.customization_group_general",
    labelKey: "pre_order.customization_section_visibility",
    icon: HideIcon,
  },
  {
    id: "advanced",
    groupKey: "pre_order.customization_group_general",
    labelKey: "pre_order.customization_section_advanced",
    icon: CodeIcon,
  },
];

// Where the script runs and the advanced switches are plain settings: no plan
// or OTP gate, unlike the copy and branding sections.
const UNGATED_UI_SECTIONS = ["visibility", "advanced"];

// Built for Shopify: no more than five form fields in a single card.
const MAX_FIELDS_PER_CARD = 5;

const chunkFields = (items, size = MAX_FIELDS_PER_CARD) => {
  const chunks = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks.length ? chunks : [[]];
};

/* Polaris 12 dropped Card's `title` prop, so every section states its own
   heading. Roomier than a default Card: the title and its one-liner sit
   together, then a clear gap before the fields. */

/**
 * The checkout widget's customization, as a modal any feature screen can open.
 * It reads and writes the shop's setting through StoreContext and saves on its
 * own, so a screen only has to say when it is open.
 */
const UiCustomizationEditor = ({
  open,
  onClose,
  isExtensionEnabled = true,
  initialSection,
}) => {
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    plan: [plan],
    shop: [shop],
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);

  const [isSaving, setIsSaving] = useState(false);
  const [selectedOtpScreen, setSelectedOtpScreen] = useState(0);

  const whatsappEnabledCountry = String(process.env.WHATSAPP_COUNTRIES || "")
    .split(",")
    .includes(shop?.country_code);

  // Defaults to on, like the column. The mark shows only while the flag is on
  // and the footer override is off, so the one switch below drives both.
  const preShowBranding =
    setting.preShowBranding ?? setting.pre_show_branding ?? true;

  // Auto-filled shipping is paid-plan and India-only, the same as on the
  // pre-order OTP screen where this setting also lives. Offering it here
  // without those gates would let a merchant switch on something the other
  // screen refuses, and the server would not honour it either.
  const isPaidPlan = useMemo(() => {
    const planName = String(plan?.name || "").toLowerCase();
    if (!planName) return false;
    return planName !== "free" && !hasNoChargeId(shop);
  }, [plan?.name, shop]);

  const isOnlyIndiaSelected = useMemo(() => {
    const raw = setting?.countryCodeList || "";
    const countries = String(raw)
      .split(",")
      .map((c) => c.trim().toUpperCase())
      .filter(Boolean);
    return countries.length === 1 && countries[0] === "IN";
  }, [setting?.countryCodeList]);

  // Mirrors UiCustomizationPlanGuard: the copy and the footer policy links are
  // on every plan, removing the COD King mark needs Pro or above.
  const canCustomizeUi = true;
  const canHideBranding = useMemo(() => {
    const planName = String(plan?.name || "")
      .trim()
      .toLowerCase()
      .replace(/\s+/g, "_");
    return (
      planName === "pro" ||
      planName === "enterprise" ||
      planName.includes("enterprise_plus")
    );
  }, [plan?.name]);

  const otpEnabledForUi = !!setting?.enablePreOrderOtp;

  const goToSubscription = useCallback((e) => {
    if (e) e.preventDefault();
    navigateTo("/subscription");
  }, []);

  const handleSettingChange = useCallback(
    (key) => (value) => {
      setSetting((prev) => ({ ...prev, [key]: value }));
      !contextualBar && setContextualBar(true);
    },
    [contextualBar, setSetting, setContextualBar]
  );

  const handleCodFormConfigChange = useCallback(
    (section, key) => (value) => {
      setSetting((prev) => {
        const cfg = prev.codFormConfig || {};
        const sectionObj = cfg[section] || {};
        return {
          ...prev,
          codFormConfig: {
            ...cfg,
            [section]: { ...sectionObj, [key]: value },
          },
        };
      });
      !contextualBar && setContextualBar(true);
    },
    [contextualBar, setSetting, setContextualBar]
  );

  // ---------------------------------------------------------------------------
  // Checkout UI customization (ui_customization jsonb): per-label overrides,
  // footer branding, and a JSON round-trip for translating everything at once.
  // ---------------------------------------------------------------------------
  const uiCustomization = useMemo(
    () => normalizeUiCustomization(setting.uiCustomization),
    [setting.uiCustomization]
  );

  const handleUiTextChange = useCallback(
    (key) => (value) => {
      setSetting((prev) => {
        const current = normalizeUiCustomization(prev.uiCustomization);
        const texts = { ...current.texts };
        // Blank clears the override so the widget falls back to the default.
        if (String(value || "").trim()) {
          texts[key] = value;
        } else {
          delete texts[key];
        }
        return { ...prev, uiCustomization: { ...current, texts } };
      });
      !contextualBar && setContextualBar(true);
    },
    [contextualBar, setSetting, setContextualBar]
  );

  const showCodKingBranding =
    preShowBranding !== false &&
    preShowBranding !== "false" &&
    uiCustomization.branding.hide_footer_branding !== true;

  // Two fields used to be able to contradict each other: the widget hides the
  // mark if either says so, so a merchant could switch branding "on" and still
  // see nothing. One switch now writes both.
  const handleBrandingVisibilityChange = useCallback(
    (value) => {
      setSetting((prev) => {
        const current = normalizeUiCustomization(prev.uiCustomization);
        return {
          ...prev,
          preShowBranding: value,
          uiCustomization: {
            ...current,
            branding: { ...current.branding, hide_footer_branding: !value },
          },
        };
      });
      !contextualBar && setContextualBar(true);
    },
    [setSetting, contextualBar, setContextualBar],
  );

  const handleUiBrandingChange = useCallback(
    (key) => (value) => {
      setSetting((prev) => {
        const current = normalizeUiCustomization(prev.uiCustomization);
        const branding = { ...current.branding };
        if (typeof value === "boolean") {
          branding[key] = value;
        } else if (String(value || "").trim()) {
          branding[key] = value.trim();
        } else {
          delete branding[key];
        }
        return { ...prev, uiCustomization: { ...current, branding } };
      });
      !contextualBar && setContextualBar(true);
    },
    [contextualBar, setSetting, setContextualBar]
  );

  // ---------------------------------------------------------------------------
  // Widget visibility (ui_customization.widget_visibility): which storefront
  // pages load the COD King script at all. Available on every plan.
  // ---------------------------------------------------------------------------
  const widgetVisibility = uiCustomization.widget_visibility;

  const setWidgetVisibility = useCallback(
    (patch) => {
      setSetting((prev) => {
        const current = normalizeUiCustomization(prev.uiCustomization);
        return {
          ...prev,
          uiCustomization: {
            ...current,
            widget_visibility: { ...current.widget_visibility, ...patch },
          },
        };
      });
      !contextualBar && setContextualBar(true);
    },
    [contextualBar, setSetting, setContextualBar]
  );

  const handleVisibilityModeChange = useCallback(
    ([mode]) => {
      // Switching back to "all pages" keeps the selection so the merchant can
      // flip it on again without re-picking everything.
      setWidgetVisibility({ mode });
    },
    [setWidgetVisibility]
  );

  const handleVisibilityPageTypesChange = useCallback(
    (pageTypes) => setWidgetVisibility({ page_types: pageTypes }),
    [setWidgetVisibility]
  );

  const [visibilityPathsDraft, setVisibilityPathsDraft] = useState(null);

  const visibilityPathsValue =
    visibilityPathsDraft ?? (widgetVisibility.paths || []).join("\n");

  // Kept as raw text while typing so "/pages/" isn't rewritten mid-keystroke,
  // but still pushed into the setting on every change — a Save that lands
  // before the blur must not lose what the merchant just typed.
  const handleVisibilityPathsChange = useCallback(
    (value) => {
      setVisibilityPathsDraft(value);
      setWidgetVisibility({
        paths: value
          .split("\n")
          .map((path) => path.trim())
          .filter(Boolean)
          .slice(0, MAX_VISIBILITY_PATHS),
      });
    },
    [setWidgetVisibility]
  );

  const commitVisibilityPaths = useCallback(() => {
    if (visibilityPathsDraft === null) return;
    setVisibilityPathsDraft(null);
    setWidgetVisibility({
      paths: visibilityPathsDraft
        .split("\n")
        .map(normalizeVisibilityPath)
        .filter((path, index, all) => path && all.indexOf(path) === index)
        .slice(0, MAX_VISIBILITY_PATHS),
    });
  }, [visibilityPathsDraft, setWidgetVisibility]);

  const [uiSection, setUiSection] = useState(UI_SECTIONS[0].id);
  // Set while a copy field has focus, so the preview shows the screen that
  // string appears on rather than whatever the rail last selected.
  const [focusedView, setFocusedView] = useState(null);
  // Bulk translate: load every label as JSON, translate the values, paste back.
  // Carried over from the old inline panel in PreOrderSetting — moving the
  // editor into this modal dropped the UI while the catalog kept exporting
  // buildBulkTexts/parseBulkTexts, leaving the feature unreachable.
  const [uiBulkJson, setUiBulkJson] = useState("");
  const [uiBulkStatus, setUiBulkStatus] = useState(null);

  // Opening from a section row lands on that section.
  useEffect(() => {
    if (open && initialSection) handleUiSectionSelect(initialSection);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, initialSection]);

  // Each section needs its own feature on before anything in it reaches a
  // customer. Rather than sending the merchant away to find the switch, the
  // section carries it: the banner turns the feature on in place, and keeps a
  // link for the cases that need more than a boolean.
  // Nothing in the editor reaches a customer until OTP verification is on, so
  // that gate is shown above every section rather than sent away to find.
  const uiSectionRequirement = useMemo(
    () => ({
      met: otpEnabledForUi,
      settingKey: "enablePreOrderOtp",
      help: I18n.t("pre_order.requires_otp_help", {
        defaultValue: "Turn on OTP verification to customize the checkout copy.",
      }),
      enableLabel: "Turn on OTP verification",
      // The widget only loads through the theme app embed, so turning OTP on
      // while the embed is off would change nothing a customer can see.
      blocked: !isExtensionEnabled,
      blockedNote:
        "Add the COD King app embed to your theme first, then turn this on.",
    }),
    [otpEnabledForUi, isExtensionEnabled]
  );

  // A section whose copy describes an optional part of the widget owns the
  // switch for it, and keeps it once it is on so it can be turned back off.
  const uiSectionFeature = useMemo(() => {
    const features = {
      coupons: {
        settingKey: "showOfferAndReward",
        title: I18n.t("ui_customization_editor.show_coupons_and_rewards"),
        description:
          I18n.t("ui_customization_editor.adds_the_coupon_and_offers_card"),
      },
      address: {
        settingKey: "isPrefilledAddressEnabled",
        title: I18n.t("pre_order.enable_prefilled"),
        description: I18n.t("pre_order.prefilled_help"),
        disabled: !isPaidPlan || !isOnlyIndiaSelected,
        disabledNote: !isPaidPlan
          ? "Auto-filled shipping needs a paid plan."
          : "Auto-filled shipping is available when India is the only country you verify.",
      },
      payments: {
        settingKey: "partialPaymentEnabled",
        title: I18n.t("ui_customization_editor.show_partial_payments"),
        description:
          I18n.t("ui_customization_editor.adds_the_payment_options_card_the"),
        path: "/features/partial-payment",
        pathLabel: I18n.t("pre_order.go_to_partial_payments", {
          defaultValue: "Go to Partial payments",
        }),
      },
    };
    const feature = features[uiSection];
    if (!feature) return null;
    return { ...feature, on: !!setting?.[feature.settingKey] };
  }, [
    uiSection,
    isPaidPlan,
    isOnlyIndiaSelected,
    setting?.showOfferAndReward,
    setting?.isPrefilledAddressEnabled,
    setting?.partialPaymentEnabled,
  ]);

  const canEditUiText = canCustomizeUi && uiSectionRequirement.met;

  // Picking a screen in the rail also moves the fields and the preview onto it.
  const handleUiSectionSelect = useCallback((id) => {
    setUiSection(id);
    setFocusedView(null);
    const section = UI_SECTIONS.find((item) => item.id === id);
    if (section && section.screen !== undefined) {
      setSelectedOtpScreen(section.screen);
    }
  }, []);

  const activeUiSection = useMemo(
    () => UI_SECTIONS.find((item) => item.id === uiSection),
    [uiSection]
  );

  // Rail badge: how much of each section the merchant has already reworded.
  const customizedCountBySection = useMemo(() => {
    const counts = {};
    UI_TEXT_GROUPS.forEach((group) => {
      const count = group.items.filter(
        (item) => (uiCustomization.texts[item.key] ?? "") !== ""
      ).length;
      counts[group.section] = (counts[group.section] || 0) + count;
    });
    return counts;
  }, [uiCustomization.texts]);

  const uiSections = useMemo(
    () =>
      UI_SECTIONS.map((section) => {
        const count = section.section
          ? customizedCountBySection[section.section] || 0
          : 0;
        return {
          ...section,
          label: section.labelKey ? I18n.t(section.labelKey) : section.label,
          group: section.groupKey ? I18n.t(section.groupKey) : section.group,
          badge: count > 0 ? String(count) : undefined,
        };
      }),
    [customizedCountBySection]
  );

  const handleDiscard = useCallback(() => {
    setSetting(originalSetting);
    setContextualBar(false);
  }, [originalSetting, setSetting, setContextualBar]);

  const handleSubmit = useCallback(async () => {
    setIsSaving(true);
    try {
      const response = await Api.post("/settings", { setting });
      setSetting(response.data);
      setOriginalSetting(response.data);
      setContextualBar(false);
    } catch (error) {
      console.error("Error saving customization:", error);
    } finally {
      setIsSaving(false);
    }
  }, [setting, setSetting, setOriginalSetting, setContextualBar]);

  const renderLegacyScreenFields = () => (
    <BlockStack gap="500">
      {selectedOtpScreen === 0 && (
        <>
          {/* WhatsApp Button Section */}
          {whatsappEnabledCountry && (
            <Card>
              <BlockStack gap="400">
                <Text variant="headingMd" as="h3">
                  {I18n.t("pre_order.enable_whatsapp")}
                </Text>
                <FormLayout>
                  <Checkbox
                    label={I18n.t("pre_order.enable_whatsapp")}
                    helpText={I18n.t("pre_order.whatsapp_help")}
                    checked={setting.preWhatsappButton}
                    onChange={handleSettingChange("preWhatsappButton")}
                  />
                  <TextField
                    label={I18n.t("pre_order.whatsapp_button_text")}
                    value={setting.preWhatsappButtonText}
                    onChange={handleSettingChange(
                      "preWhatsappButtonText"
                    )}
                    placeholder={I18n.t(
                      "pre_order.whatsapp_button_placeholder"
                    )}
                    helpText={I18n.t("pre_order.whatsapp_button_help")}
                  />
                </FormLayout>
              </BlockStack>
            </Card>
          )}
          {/* Skip Button Section */}
          <Card>
            <BlockStack gap="400">
              <Text variant="headingMd" as="h3">
                {I18n.t("pre_order.skip_button_options")}
              </Text>
              <FormLayout>
                <Checkbox
                  label={I18n.t("pre_order.show_skip_button")}
                  helpText={I18n.t("pre_order.show_skip_button_help")}
                  checked={setting.preShowSkipBtn}
                  onChange={handleSettingChange("preShowSkipBtn")}
                />
                <TextField
                  label={I18n.t("pre_order.skip_button_text")}
                  value={setting.preSkipBtnText}
                  onChange={handleSettingChange("preSkipBtnText")}
                  placeholder={I18n.t(
                    "pre_order.skip_button_placeholder"
                  )}
                  helpText={I18n.t("pre_order.skip_button_help")}
                />
              </FormLayout>
            </BlockStack>
          </Card>
          {/* Phone Screen Content - Part 2 */}
          <Card>
            <FormLayout>
              <TextField
                label={I18n.t("pre_order.phone_placeholder")}
                value={setting.prePhonePlaceholder}
                onChange={handleSettingChange("prePhonePlaceholder")}
                placeholder={I18n.t("pre_order.phone")}
                helpText={I18n.t("pre_order.phone_label")}
              />
              <TextField
                label={I18n.t("pre_order.invalid_phone")}
                value={setting.preInvalidPhone}
                onChange={handleSettingChange("preInvalidPhone")}
                placeholder={I18n.t(
                  "pre_order.invalid_phone_placeholder"
                )}
                helpText={I18n.t("pre_order.invalid_phone_help")}
              />
            </FormLayout>
          </Card>
          {/* Button Labels */}
          <Card>
            <BlockStack gap="400">
              <Text variant="headingMd" as="h3">
                {I18n.t("pre_order.button_labels")}
              </Text>
              <FormLayout>
                <TextField
                  label={I18n.t("pre_order.send_code_label")}
                  value={setting.preSendButtonLabel}
                  onChange={handleSettingChange("preSendButtonLabel")}
                  placeholder={I18n.t("pre_order.send_code")}
                />
                <TextField
                  label={I18n.t("pre_order.verify_code_label")}
                  value={setting.preVerifyButtonLabel}
                  onChange={handleSettingChange("preVerifyButtonLabel")}
                  placeholder={I18n.t("pre_order.verify_code")}
                />
              </FormLayout>
            </BlockStack>
          </Card>
          {/* Phone Screen Content - Heading and Subheading */}
          <Card>
            <BlockStack gap="400">
              <Text variant="headingMd" as="h3">
                {I18n.t("pre_order.phone_screen_content")}
              </Text>
              <FormLayout>
                <TextField
                  label={I18n.t("pre_order.otp_box_heading")}
                  value={setting.preHeading}
                  onChange={handleSettingChange("preHeading")}
                  placeholder={I18n.t("pre_order.otp_box_placeholder")}
                  helpText={I18n.t("pre_order.otp_box_help")}
                />
                <TextField
                  label={I18n.t("pre_order.subheading")}
                  value={setting.preSubHeading}
                  onChange={handleSettingChange("preSubHeading")}
                  placeholder={I18n.t("pre_order.subheading_placeholder")}
                  helpText={I18n.t("pre_order.subheading_help")}
                />
              </FormLayout>
            </BlockStack>
          </Card>
          {/* Button Styling */}
          <Card>
            <BlockStack gap="400">
              <Text variant="headingMd" as="h3">
                {I18n.t("pre_order.button_styling")}
              </Text>
              <FormLayout>
                <InlineStack gap="400" align="start">
                  <HexColorPicker
                    color={setting.prePrimaryButtonColor || "#666666"}
                    label={I18n.t("pre_order.primary_button_color")}
                    onChange={handleSettingChange(
                      "prePrimaryButtonColor"
                    )}
                  />
                  <HexColorPicker
                    color={setting.prePrimaryButtonFontColor || "#666666"}
                    label={I18n.t("pre_order.primary_button_font_color")}
                    onChange={handleSettingChange(
                      "prePrimaryButtonFontColor"
                    )}
                  />
                </InlineStack>
              </FormLayout>
            </BlockStack>
          </Card>
        </>
      )}
      {selectedOtpScreen === 1 && (
        <>
          {/* Verification Screen Content */}
          <Card>
            <BlockStack gap="400">
              <Text variant="headingMd" as="h3">
                {I18n.t("pre_order.verification_content")}
              </Text>
              <FormLayout>
                <TextField
                  label={I18n.t("pre_order.verify_phone_heading")}
                  value={setting.preVerifyMobile}
                  onChange={handleSettingChange("preVerifyMobile")}
                  placeholder={I18n.t("pre_order.verify_mobile")}
                  helpText={I18n.t("pre_order.verify_phone_help")}
                />
                <TextField
                  label={I18n.t("pre_order.enter_code_text")}
                  value={setting.preEnterCode}
                  onChange={handleSettingChange("preEnterCode")}
                  placeholder={I18n.t("pre_order.enter_code_placeholder")}
                  helpText={I18n.t("pre_order.enter_code_help")}
                />
              </FormLayout>
            </BlockStack>
          </Card>
          {/* Verification Actions */}
          <Card>
            <BlockStack gap="400">
              <Text variant="headingMd" as="h3">
                {I18n.t("pre_order.verification_actions")}
              </Text>
              <FormLayout>
                <TextField
                  label={I18n.t("pre_order.resend_button_text")}
                  value={setting.preResend}
                  onChange={handleSettingChange("preResend")}
                  placeholder={I18n.t("pre_order.resend")}
                  helpText={I18n.t("pre_order.resend_help")}
                />
                <TextField
                  label={I18n.t("pre_order.invalid_otp_message")}
                  value={setting.preInvalidOtpMsg}
                  onChange={handleSettingChange("preInvalidOtpMsg")}
                  placeholder={I18n.t("pre_order.invalid_otp")}
                  helpText={I18n.t("pre_order.invalid_otp_help")}
                />
              </FormLayout>
            </BlockStack>
          </Card>
        </>
      )}
      {selectedOtpScreen === 2 && (
        <>
          {/* Success Messages */}
          <Card>
            <BlockStack gap="400">
              <Text variant="headingMd" as="h3">
                {I18n.t("pre_order.success_messages")}
              </Text>
              <FormLayout>
                <TextField
                  label={I18n.t("pre_order.redirect_message")}
                  value={setting.preRedirectText}
                  onChange={handleSettingChange("preRedirectText")}
                  placeholder={I18n.t("pre_order.redirect_placeholder")}
                  helpText={I18n.t("pre_order.redirect_help")}
                />
                <TextField
                  label={I18n.t("pre_order.success_message")}
                  value={setting.preSuccessMessage}
                  onChange={handleSettingChange("preSuccessMessage")}
                  placeholder={I18n.t(
                    "pre_order.success_message_placeholder"
                  )}
                  helpText={I18n.t("pre_order.success_message_help")}
                />
                <TextField
                  label={I18n.t("pre_order.continue_button_text")}
                  value={setting.preContinueButtonText}
                  onChange={handleSettingChange("preContinueButtonText")}
                  placeholder={I18n.t(
                    "pre_order.continue_button_placeholder"
                  )}
                  helpText={I18n.t("pre_order.continue_button_help")}
                />
              </FormLayout>
            </BlockStack>
          </Card>
          {/* Success Button Styling */}
          <Card>
            <BlockStack gap="400">
              <Text variant="headingMd" as="h3">
                {I18n.t("pre_order.success_button_styling")}
              </Text>
              <FormLayout>
                <InlineStack gap="400" align="start">
                  <HexColorPicker
                    color={setting.preSuccessButtonColor || "#28a745"}
                    label={I18n.t("pre_order.success_button_color")}
                    onChange={handleSettingChange(
                      "preSuccessButtonColor"
                    )}
                  />
                  <HexColorPicker
                    color={setting.preSuccessButtonFontColor || "#ffffff"}
                    label={I18n.t("pre_order.success_button_font_color")}
                    onChange={handleSettingChange(
                      "preSuccessButtonFontColor"
                    )}
                  />
                </InlineStack>
              </FormLayout>
            </BlockStack>
          </Card>
        </>
      )}
    </BlockStack>
  );

  /* Only the settings the widget still reads and the copy catalog does not
     already cover. Everything else it used to show was either dead in
     notifik-svelte-app or a second editor for a string uiText() resolves from
     ui_customization.texts first. */
  /* Only the settings the widget still reads and the copy catalog does not
     already cover. Everything else it used to show was either dead in
     notifik-svelte-app or a second editor for a string uiText() resolves from
     ui_customization.texts first. */

  const renderScreenFields = () => (
    <BlockStack gap="500">
      {selectedOtpScreen === 0 && (
        <>
          <SectionCard>
            <BlockStack gap="500">
              <SettingGroup title={I18n.t("ui_customization_editor.buttons_and_fields")}>
                <FormLayout>
                  <TextField
                    label={I18n.t("pre_order.send_code_label")}
                    value={setting.preSendButtonLabel}
                    onChange={handleSettingChange("preSendButtonLabel")}
                    placeholder={I18n.t("pre_order.send_code")}
                    helpText={I18n.t("ui_customization_editor.the_main_button_that_sends_the")}
                    autoComplete="off"
                  />
                  <TextField
                    label={I18n.t("pre_order.phone_placeholder")}
                    value={setting.prePhonePlaceholder}
                    onChange={handleSettingChange("prePhonePlaceholder")}
                    placeholder={I18n.t("pre_order.phone")}
                    helpText={I18n.t("ui_customization_editor.grey_hint_inside_the_empty_phone")}
                    autoComplete="off"
                  />
                  {!setting.preIsNewDesignEnabled && (
                    <InlineStack align="space-between">
                      <HexColorPicker
                        color={setting.prePrimaryButtonColor || "#666666"}
                        label={I18n.t("pre_order.primary_button_color")}
                        onChange={handleSettingChange("prePrimaryButtonColor")}
                      />
                      <HexColorPicker
                        color={setting.prePrimaryButtonFontColor || "#666666"}
                        label={I18n.t("pre_order.primary_button_font_color")}
                        onChange={handleSettingChange(
                          "prePrimaryButtonFontColor"
                        )}
                      />
                    </InlineStack>
                  )}
                </FormLayout>
              </SettingGroup>
            </BlockStack>
          </SectionCard>

          <SectionCard>
            <BlockStack gap="500">
              {whatsappEnabledCountry && (
                <>
                  <SettingGroup title={I18n.t("ui_customization_editor.whatsapp")}>
                    <SettingRow
                      title={I18n.t("pre_order.enable_whatsapp")}
                      description={I18n.t("ui_customization_editor.adds_whatsapp_beside_the_send_code")}
                      control={
                        <Checkbox
                          label={I18n.t("pre_order.enable_whatsapp")}
                          labelHidden
                          checked={setting.preWhatsappButton}
                          onChange={handleSettingChange("preWhatsappButton")}
                        />
                      }
                    />
                    <SettingRow
                      title={I18n.t("pre_order.whatsapp_primary")}
                      description={I18n.t("pre_order.whatsapp_primary_help")}
                      control={
                        <Checkbox
                          label={I18n.t("pre_order.whatsapp_primary")}
                          labelHidden
                          checked={uiCustomization.branding.whatsapp_primary === true}
                          onChange={handleUiBrandingChange("whatsapp_primary")}
                          disabled={!setting.preWhatsappButton}
                        />
                      }
                    />
                  </SettingGroup>
                  <Divider />
                </>
              )}

              <SettingGroup title={I18n.t("ui_customization_editor.skip_verification")}>
                <SettingRow
                  title={I18n.t("pre_order.show_skip_button")}
                  description={I18n.t("pre_order.show_skip_button_help")}
                  control={
                    <Checkbox
                      label={I18n.t("pre_order.show_skip_button")}
                      labelHidden
                      checked={setting.preShowSkipBtn}
                      onChange={handleSettingChange("preShowSkipBtn")}
                    />
                  }
                >
                  {setting.preShowSkipBtn && (
                    <TextField
                      label={I18n.t("pre_order.skip_button_text")}
                      value={setting.preSkipBtnText}
                      onChange={handleSettingChange("preSkipBtnText")}
                      placeholder={I18n.t("pre_order.skip_button_placeholder")}
                      autoComplete="off"
                    />
                  )}
                </SettingRow>
              </SettingGroup>

            </BlockStack>
          </SectionCard>
        </>
      )}

      {selectedOtpScreen === 1 && (
        <>
          <SectionCard>
            <SettingGroup title={I18n.t("ui_customization_editor.messages_on_this_screen")}>
              <FormLayout>
                <TextField
                  label={I18n.t("pre_order.verify_phone_heading")}
                  value={setting.preVerifyMobile}
                  onChange={handleSettingChange("preVerifyMobile")}
                  placeholder={I18n.t("pre_order.verify_mobile")}
                  autoComplete="off"
                />
                <TextField
                  label={I18n.t("pre_order.enter_code_text")}
                  value={setting.preEnterCode}
                  onChange={handleSettingChange("preEnterCode")}
                  placeholder={I18n.t("pre_order.enter_code_placeholder")}
                  autoComplete="off"
                />
                <TextField
                  label={I18n.t("pre_order.retry_in_text")}
                  value={setting.preRetryIn}
                  onChange={handleSettingChange("preRetryIn")}
                  placeholder={I18n.t("pre_order.retry_in_placeholder")}
                  helpText={I18n.t("ui_customization_editor.counts_down_before_the_code_can")}
                  autoComplete="off"
                />
                <TextField
                  label={I18n.t("pre_order.verifying_button_text")}
                  value={setting.preVerifying}
                  onChange={handleSettingChange("preVerifying")}
                  placeholder={I18n.t("pre_order.verifying")}
                  helpText={I18n.t("ui_customization_editor.on_the_button_while_the_code")}
                  autoComplete="off"
                />
              </FormLayout>
            </SettingGroup>
          </SectionCard>

          {/* Kept apart so neither card runs past five fields. */}
          <SectionCard>
            <SettingGroup title={I18n.t("ui_customization_editor.error_messages")}>
              <FormLayout>
                <TextField
                  label={I18n.t("pre_order.invalid_otp_message")}
                  value={setting.preInvalidOtpMsg}
                  onChange={handleSettingChange("preInvalidOtpMsg")}
                  placeholder={I18n.t("pre_order.invalid_otp")}
                  helpText={I18n.t("ui_customization_editor.shown_when_the_code_entered_is")}
                  autoComplete="off"
                />
                <TextField
                  label={I18n.t("pre_order.invalid_phone")}
                  value={setting.preInvalidPhone}
                  onChange={handleSettingChange("preInvalidPhone")}
                  placeholder={I18n.t("pre_order.invalid_phone_placeholder")}
                  helpText={I18n.t("ui_customization_editor.shown_under_the_phone_field_when")}
                  autoComplete="off"
                />
              </FormLayout>
            </SettingGroup>
          </SectionCard>
        </>
      )}
    </BlockStack>
  );

  // Plan and OTP gating is shown, never hidden  // Plan and OTP gating is shown, never hidden  // Plan and OTP gating is shown, never hidden  // Plan and OTP gating is shown, never hidden  // Plan and OTP gating is shown, never hidden — it applies to every section,
  // so it sits above whichever one the rail has selected.
  const renderUiGating = () => {
    if (uiSectionRequirement.met) return null;

    return (
      <Banner status="warning">
        <BlockStack gap="300">
          <Text variant="bodyMd" as="p">
            {uiSectionRequirement.help}
          </Text>
          <Checkbox
            label={uiSectionRequirement.enableLabel}
            checked={false}
            disabled={uiSectionRequirement.blocked}
            onChange={() =>
              handleSettingChange(uiSectionRequirement.settingKey)(true)
            }
          />
          {uiSectionRequirement.blocked && (
            <Text variant="bodySm" tone="subdued" as="p">
              {uiSectionRequirement.blockedNote}
            </Text>
          )}
        </BlockStack>
      </Banner>
    );
  };

  // The switch for the part of the widget this section describes, above its
  // fields so the answer to "why does none of this show?" is the first thing
  // on the page.
  const renderSectionFeature = () => {
    if (!uiSectionFeature) return null;

    return (
      <SectionCard>
        <SettingGroup>
          <SettingRow
            title={uiSectionFeature.title}
            description={uiSectionFeature.description}
            control={
              <Checkbox
                label={uiSectionFeature.title}
                labelHidden
                checked={uiSectionFeature.on}
                disabled={uiSectionFeature.disabled === true}
                onChange={handleSettingChange(uiSectionFeature.settingKey)}
              />
            }
          />
          {uiSectionFeature.disabled && uiSectionFeature.disabledNote && (
            <Text variant="bodySm" tone="subdued" as="p">
              {uiSectionFeature.disabledNote}
            </Text>
          )}
          {uiSectionFeature.path && (
            <Link
              onClick={() => {
                onClose();
                navigateTo(uiSectionFeature.path);
              }}
            >
              {uiSectionFeature.pathLabel}
            </Link>
          )}
        </SettingGroup>
      </SectionCard>
    );
  };

  // Footer links go straight into the storefront widget's anchor hrefs, so a
  // typo ships a dead link to shoppers. Blank is valid — the widget falls back
  // to the COD King policy — but anything typed must be an absolute http(s) URL.
  const linkUrlError = (value) => {
    const url = String(value ?? "").trim();
    if (!url) return undefined;
    let parsed;
    try {
      parsed = new URL(url);
    } catch {
      return "Enter a full URL, starting with https://";
    }
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
      return "Only http:// and https:// links work here";
    }
    if (!parsed.hostname.includes(".")) {
      return "Enter a full URL, starting with https://";
    }
    return undefined;
  };

  const renderUiBrandingSection = () => (
    <SectionCard>
      <BlockStack gap="500">
        <SettingGroup title={I18n.t("ui_customization_editor.logo_and_name")}>
          <FormLayout>
            <TextField
              label={I18n.t("pre_order.store_name")}
              value={setting.preV2Title}
              onChange={handleSettingChange("preV2Title")}
              helpText={I18n.t("ui_customization_editor.shown_beside_your_logo_at_the")}
              autoComplete="off"
            />
            <TextField
              label={I18n.t("pre_order.brand_logo")}
              value={setting.brandLogoUrl}
              onChange={handleSettingChange("brandLogoUrl")}
              helpText={I18n.t("ui_customization_editor.direct_link_to_a_png_or")}
              autoComplete="off"
            />
          </FormLayout>
        </SettingGroup>

        <Divider />

        <SettingGroup title={I18n.t("ui_customization_editor.brand_color")}>
          <BlockStack gap="200">
            <Text as="p" variant="bodySm" tone="subdued">
              {I18n.t("ui_customization_editor.brand_color_help")}
            </Text>
            <InlineStack gap="400" align="start" blockAlign="end">
              <HexColorPicker
                color={uiCustomization.branding.brand_color || UI_DEFAULT_BRAND_COLOR}
                label={I18n.t("ui_customization_editor.brand_color")}
                onChange={handleUiBrandingChange("brand_color")}
              />
              {uiCustomization.branding.brand_color && (
                <Button variant="plain" onClick={() => handleUiBrandingChange("brand_color")("")}>
                  {I18n.t("ui_customization_editor.reset_to_default")}
                </Button>
              )}
            </InlineStack>
          </BlockStack>
        </SettingGroup>

        <Divider />

        <SettingGroup title={I18n.t("pre_order.promo_banner_settings_title")}>
          <SettingRow
            title={I18n.t("pre_order.show_promo_banner")}
            description={I18n.t("pre_order.show_promo_banner_help")}
            control={
              <Checkbox
                label={I18n.t("pre_order.show_promo_banner")}
                labelHidden
                checked={setting.promoBannerShow}
                onChange={handleSettingChange("promoBannerShow")}
              />
            }
          >
            {setting.promoBannerShow && (
              <FormLayout>
                <TextField
                  label={I18n.t("pre_order.promo_banner_text")}
                  value={setting.promoBannerText}
                  onChange={handleSettingChange("promoBannerText")}
                  placeholder={I18n.t("pre_order.promo_banner_text_placeholder")}
                  autoComplete="off"
                />
                {/* The widget also paints its header in the banner colour. */}
                <InlineStack gap="400" align="start">
                  <HexColorPicker
                    color={setting.promoBannerColor || "#dc2626"}
                    label={I18n.t("pre_order.banner_background_color")}
                    onChange={handleSettingChange("promoBannerColor")}
                  />
                  <HexColorPicker
                    color={setting.promoTextColor || "#ffffff"}
                    label={I18n.t("pre_order.banner_text_color")}
                    onChange={handleSettingChange("promoTextColor")}
                  />
                </InlineStack>
              </FormLayout>
            )}
          </SettingRow>
        </SettingGroup>

        <Divider />

        <SettingGroup title={I18n.t("ui_customization_editor.cod_king_branding")}>
          <SettingRow
            title={I18n.t("ui_customization_editor.show_cod_king_branding")}
            description={I18n.t("ui_customization_editor.the_cod_king_name_and_logo")}
            control={
              <Checkbox
                label={I18n.t("ui_customization_editor.show_cod_king_branding")}
                labelHidden
                checked={showCodKingBranding}
                onChange={handleBrandingVisibilityChange}
                disabled={!canHideBranding}
              />
            }
          />
          {!canHideBranding && (
            <Text as="p" variant="bodySm" tone="subdued">
              {I18n.t("pre_order.hide_branding_requires_pro")}{" "}
              <Link url="/subscription" onClick={goToSubscription}>
                {I18n.t("pre_order.upgrade_to_hide_branding")}
              </Link>
            </Text>
          )}
        </SettingGroup>

        <Divider />

        <SettingGroup title={I18n.t("ui_customization_editor.footer_links")}>
          <FormLayout>
            <FormLayout.Group>
              <TextField
                label={I18n.t("ui_customization_editor.terms_conditions_url")}
                value={uiCustomization.branding.terms_url ?? ""}
                onChange={handleUiBrandingChange("terms_url")}
                error={linkUrlError(uiCustomization.branding.terms_url)}
                placeholder="https://your-store.com/policies/terms-of-service"
                helpText={I18n.t("ui_customization_editor.leave_blank_to_link_to_the")}
                autoComplete="off"
              />
              <TextField
                label={I18n.t("ui_customization_editor.privacy_policy_url")}
                value={uiCustomization.branding.privacy_url ?? ""}
                onChange={handleUiBrandingChange("privacy_url")}
                error={linkUrlError(uiCustomization.branding.privacy_url)}
                placeholder="https://your-store.com/policies/privacy-policy"
                autoComplete="off"
              />
            </FormLayout.Group>
          </FormLayout>
        </SettingGroup>
      </BlockStack>
    </SectionCard>
  );

  // Copy for whichever screen the rail has selected, from the shared catalog.
  // Copy for the active section, from the shared catalog. Each topic gets its
  // own card, with its fields on show: the merchant reads one list per topic
  // instead of hunting through a separate collapsed "wording" panel for the
  // other half of the same setting.
  const renderUiCopyFields = () => {
    const groups = UI_TEXT_GROUPS.filter(
      (group) => group.section === activeUiSection?.section
    );
    if (groups.length === 0) return null;

    const fields = groups.reduce((total, group) => total + group.items.length, 0);
    const customized = groups.reduce(
      (total, group) =>
        total +
        group.items.filter(
          (item) => (uiCustomization.texts[item.key] ?? "") !== ""
        ).length,
      0
    );

    return (
      <BlockStack gap="500">
        {/* Said once for the whole section. It used to repeat under every
            card heading, which buried the line that actually described the
            card. */}
        <Text variant="bodySm" tone="subdued" as="p">
          {customized > 0
            ? `${customized} of ${fields} changed. Blank fields keep the grey default, and {{curly braces}} fill in automatically.`
            : "Blank fields keep the grey default. {{curly braces}} fill in automatically."}
        </Text>

        {groups.flatMap((group) => {
          // Groups are written to fit in a card; this only catches one that
          // grows past the Built for Shopify limit later.
          const chunks = chunkFields(group.items);
          return chunks.map((items, index) => (
            <SectionCard
              key={`${group.title}-${index}`}
              title={
                chunks.length > 1
                  ? `${group.title} (${index + 1} of ${chunks.length})`
                  : group.title
              }
              description={index === 0 ? group.help : undefined}
            >
              <FormLayout>
                {items.map((item) => (
                  <TextField
                    key={item.key}
                    label={item.label}
                    value={uiCustomization.texts[item.key] ?? ""}
                    onChange={handleUiTextChange(item.key)}
                    onFocus={() => setFocusedView(group.preview || null)}
                    placeholder={item.default}
                    helpText={item.help}
                    disabled={!canEditUiText}
                    autoComplete="off"
                  />
                ))}
              </FormLayout>
            </SectionCard>
          ));
        })}
      </BlockStack>
    );
  };

  // Which storefront pages load the script at all (ui_customization.widget_visibility).
  const renderUiVisibilitySection = () => (
    <SectionCard
      title={I18n.t("pre_order.customization_section_visibility")}
      description={I18n.t("ui_customization_editor.the_widget_loads_on_every_page")}
    >
      <BlockStack gap="400">
        <ChoiceList
            title={I18n.t("ui_customization_editor.pages")}
            titleHidden
            choices={[
              {
                label: I18n.t("ui_customization_editor.all_pages_recommended"),
                value: "all",
              },
              {
                label: I18n.t("ui_customization_editor.all_pages_except_the_ones_i"),
                value: "exclude",
              },
              {
                label: I18n.t("ui_customization_editor.only_the_pages_i_select"),
                value: "include",
              },
            ]}
            selected={[widgetVisibility.mode]}
            onChange={handleVisibilityModeChange}
          />

          {widgetVisibility.mode !== "all" && (
            <>
              <Divider />
              <BlockStack gap="300">
                <Text variant="headingSm" as="h4">
                  {widgetVisibility.mode === "include"
                    ? "Run only on these pages"
                    : "Do not run on these pages"}
                </Text>
                <ChoiceList
                  title={I18n.t("ui_customization_editor.page_types")}
                  titleHidden
                  allowMultiple
                  choices={UI_VISIBILITY_PAGE_TYPES.map((type) => ({
                    label: type.label,
                    value: type.value,
                  }))}
                  selected={widgetVisibility.page_types}
                  onChange={handleVisibilityPageTypesChange}
                />
                <TextField
                  label={I18n.t("ui_customization_editor.specific_urls")}
                  value={visibilityPathsValue}
                  onChange={handleVisibilityPathsChange}
                  onBlur={commitVisibilityPaths}
                  multiline={4}
                  monospaced
                  placeholder={"/pages/about\n/blogs/news/*"}
                  helpText={`One path per line, without your domain. Use * at the end to match everything below it — /pages/* covers every static page. Up to ${MAX_VISIBILITY_PATHS} paths.`}
                  autoComplete="off"
                />
                {widgetVisibility.page_types.length === 0 &&
                  (widgetVisibility.paths || []).length === 0 && (
                    <Banner status="warning">
                      <Text variant="bodyMd">
                        {I18n.t("ui_customization_editor.nothing_selected_yet_the_script_keeps")}
                      </Text>
                    </Banner>
                  )}
              </BlockStack>
            </>
          )}
      </BlockStack>
    </SectionCard>
  );

  // Everything that used to sit behind the Advanced settings tab.
  const loadUiBulkJson = useCallback(() => {
    setUiBulkJson(JSON.stringify(buildBulkTexts(uiCustomization.texts), null, 2));
    setUiBulkStatus(null);
  }, [uiCustomization.texts]);

  const applyUiBulkJson = useCallback(() => {
    let parsed;
    try {
      parsed = JSON.parse(uiBulkJson);
    } catch (e) {
      setUiBulkStatus({
        status: "critical",
        message: I18n.t("ui_customization_editor.bulk_invalid_json"),
      });
      return;
    }
    const { texts, resetKeys, unknownKeys, count } = parseBulkTexts(parsed);
    setSetting((prev) => {
      const current = normalizeUiCustomization(prev.uiCustomization);
      const next = { ...current.texts, ...texts };
      resetKeys.forEach((k) => delete next[k]);
      return { ...prev, uiCustomization: { ...current, texts: next } };
    });
    !contextualBar && setContextualBar(true);
    setUiBulkStatus({
      status: unknownKeys.length ? "warning" : "success",
      message: I18n.t("ui_customization_editor.bulk_applied", {
        count,
        reset: resetKeys.length,
        unknown: unknownKeys.length,
      }),
    });
  }, [uiBulkJson, setSetting, contextualBar, setContextualBar]);

  const renderUiBulkSection = () => (
    <SectionCard
      title={I18n.t("ui_customization_editor.bulk_translate_title")}
      description={I18n.t("ui_customization_editor.bulk_translate_description")}
    >
      <FormLayout>
        <TextField
          label={I18n.t("ui_customization_editor.bulk_labels_json")}
          value={uiBulkJson}
          onChange={setUiBulkJson}
          multiline={8}
          monospaced
          disabled={!canEditUiText}
          autoComplete="off"
        />
        <InlineStack gap="200">
          <Button onClick={loadUiBulkJson} disabled={!canEditUiText}>
            {I18n.t("ui_customization_editor.bulk_load_current")}
          </Button>
          <Button
            variant="primary"
            onClick={applyUiBulkJson}
            disabled={!canEditUiText || !uiBulkJson.trim()}
          >
            {I18n.t("ui_customization_editor.bulk_apply")}
          </Button>
        </InlineStack>
        {uiBulkStatus && (
          <Banner tone={uiBulkStatus.status}>
            <Text as="p" variant="bodyMd">
              {uiBulkStatus.message}
            </Text>
          </Banner>
        )}
      </FormLayout>
    </SectionCard>
  );

  const renderUiAdvancedSection = () => (
    <BlockStack gap="500">
      <SectionCard
        title={I18n.t("pre_order.customization_section_advanced")}
        description={I18n.t("ui_customization_editor.behaviour_of_the_popup_itself_and")}
      >
        <SettingRow
          title={I18n.t("ui_customization_editor.open_the_popup_instantly_on_buy")}
          description={I18n.t("ui_customization_editor.the_popup_appears_straight_away_and")}
          control={
            <Checkbox
              label={I18n.t("ui_customization_editor.optimized_buy_now")}
              labelHidden
              checked={
                setting.optimizedBuyNow === true ||
                setting.optimized_buy_now === true
              }
              onChange={handleSettingChange("optimized_buy_now")}
            />
          }
        />
      </SectionCard>

    </BlockStack>
  );

  // Hint text shown inside each empty address field. The labels above them are
  // edited under Wording on this screen, which the widget reads first.
  // Address has no settings card of its own: the inputs use a floating label,
  // so what a customer reads in an empty field is the label, and those are
  // edited as copy below, where they live in ui_customization.texts as addr_*.

  // GST belongs with the address form it appears in: it used to render in
  // renderScreenFields, which put it on all three screen sections and none
  // of them previews the address form, so the field could not be seen.
  const renderGstSection = () => (
    <BlockStack gap="500">
    {setting.isPrefilledAddressEnabled && (
      <SectionCard
        title={I18n.t("ui_customization_editor.gst_number_field")}
        description={I18n.t("ui_customization_editor.collect_a_gst_number_from_customers")}
      >
        <SettingRow
          title={I18n.t("ui_customization_editor.show_a_gst_number_field_in")}
          description={I18n.t("ui_customization_editor.lets_customers_enter_their_gst_details")}
          control={
            <Checkbox
              label={I18n.t("ui_customization_editor.show_gst_field")}
              labelHidden
              checked={setting.codFormConfig?.gst?.enabled === true}
              onChange={handleCodFormConfigChange("gst", "enabled")}
            />
          }
        />
        <FormLayout>
          {setting.codFormConfig?.gst?.enabled && (
            <>
              <TextField
                label={I18n.t("ui_customization_editor.field_label")}
                value={setting.codFormConfig?.gst?.label ?? ""}
                onChange={handleCodFormConfigChange("gst", "label")}
                placeholder={I18n.t("ui_customization_editor.gst_number")}
                autoComplete="off"
              />
              <TextField
                label={I18n.t("ui_customization_editor.placeholder")}
                value={setting.codFormConfig?.gst?.placeholder ?? ""}
                onChange={handleCodFormConfigChange("gst", "placeholder")}
                placeholder={I18n.t("ui_customization_editor.e_g_22aaaaa0000a1z5")}
                autoComplete="off"
              />
              <Checkbox
                label={I18n.t("ui_customization_editor.make_it_required")}
                helpText={I18n.t("ui_customization_editor.customers_must_enter_a_valid_15")}
                checked={setting.codFormConfig?.gst?.required === true}
                onChange={handleCodFormConfigChange("gst", "required")}
              />
            </>
          )}
        </FormLayout>
      </SectionCard>
    )}
    </BlockStack>
  );

  const renderUiModal = () => {
    const isScreenSection = activeUiSection?.screen !== undefined;
    // The preview draws the redesigned widget, so it only matches that path.
    const isNewDesign = !!setting?.preIsNewDesignEnabled;

    return (
      <UiCustomizationModal
        open={open}
        title={I18n.t("pre_order.customization")}
        titleIcon={PaintBrushFlatIcon}
        titleBadge={
          <Badge
            tone={isExtensionEnabled ? "success" : "attention"}
            progress={isExtensionEnabled ? "complete" : "incomplete"}
          >
            {isExtensionEnabled
              ? I18n.t("pre_order.status_on")
              : I18n.t("pre_order.status_off")}
          </Badge>
        }
        sections={uiSections}
        activeSection={uiSection}
        onSelectSection={handleUiSectionSelect}
        onClose={onClose}
        onSave={handleSubmit}
        onDiscard={handleDiscard}
        isSaving={isSaving}
        isDirty={contextualBar}
        footerHelp={I18n.t("pre_order.customization_footer_help")}
        preview={
          isNewDesign ? (
            <LiveWidgetPreview
              setting={setting}
              screen={focusedView || activeUiSection?.previewScreen}
            />
          ) : null
        }
      >
        <BlockStack gap="500">
          {!UNGATED_UI_SECTIONS.includes(uiSection) && renderUiGating()}
          {renderSectionFeature()}
          {uiSection === "branding" && renderUiBrandingSection()}
          {uiSection === "address" && renderGstSection()}
          {isScreenSection &&
            (isNewDesign ? renderScreenFields() : renderLegacyScreenFields())}
          {uiSection === "visibility" && renderUiVisibilitySection()}
          {uiSection === "advanced" && renderUiAdvancedSection()}
          {uiSection === "advanced" && renderUiBulkSection()}
          {renderUiCopyFields()}
        </BlockStack>
      </UiCustomizationModal>
    );
  };

  return renderUiModal();
};

/** The editor's table of contents, for a screen that lists what it can open. */
export const UiCustomizationSectionList = ({ onOpen, disabled = false }) => {
  const {
    setting: [setting],
  } = useContext(StoreContext);

  const uiCustomization = useMemo(
    () => normalizeUiCustomization(setting.uiCustomization),
    [setting.uiCustomization]
  );

  const customizedCountBySection = useMemo(() => {
    const counts = {};
    UI_TEXT_GROUPS.forEach((group) => {
      const count = group.items.filter(
        (item) => (uiCustomization.texts[item.key] ?? "") !== ""
      ).length;
      counts[group.section] = (counts[group.section] || 0) + count;
    });
    return counts;
  }, [uiCustomization.texts]);

  const sections = UI_SECTIONS;

  return (
    <SectionCard
      title={I18n.t("pre_order.customization_sections_title")}
      description={I18n.t("pre_order.customization_sections_help")}
    >
      <BlockStack gap="0">
        {sections.map((section, index) => {
          const count = section.section
            ? customizedCountBySection[section.section] || 0
            : 0;
          return (
            <Box
              key={section.id}
              borderBlockStartWidth={index === 0 ? "0" : "025"}
              borderColor="border"
              paddingBlock="300"
            >
              <InlineStack align="space-between" blockAlign="center" gap="400">
                <InlineStack gap="300" blockAlign="center">
                  <Box width="20px">
                    <Icon source={section.icon} tone="subdued" />
                  </Box>
                  <Text variant="bodyMd" as="span">
                    {section.labelKey ? I18n.t(section.labelKey) : section.label}
                  </Text>
                  {count > 0 && <Badge tone="info">{String(count)}</Badge>}
                </InlineStack>
                <Button
                  variant="tertiary"
                  disabled={disabled}
                  onClick={() => onOpen(section.id)}
                >
                  {I18n.t("pre_order.customize")}
                </Button>
              </InlineStack>
            </Box>
          );
        })}
      </BlockStack>
    </SectionCard>
  );
};

export default UiCustomizationEditor;
