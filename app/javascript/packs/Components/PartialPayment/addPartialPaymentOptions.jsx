import React, {
  useState,
  useEffect,
  useRef,
  useContext,
  useCallback,
} from "react";
import {
  Button,
  Select,
  TextField,
  Checkbox,
  ChoiceList,
  InlineStack,
  BlockStack,
  Page,
  Box,
  Text,
  Link,
  InlineGrid,
  Card,
  Divider,
  Layout,
  Banner,
  InlineError,
} from "@shopify/polaris";
// 1. Updated App Bridge imports
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import I18n from "../../i18n-lang";
import FeatureCallout from "../FeatureCallout";
import { StoreContext } from "../../Context/Store";
import { hasNoChargeId } from "../../utils/shopUtils";
import Api from "../../Services/Api";

// Shown in the callout panel at 290x210.
const PARTIAL_PAYMENT_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-10_at_1.30.54_PM.jpg?v=1789127006";

export default function AddPaymentOptions({
  handleCreate,
  handleUpdate,
  onBack,
  initialData,
}) {
  const shopify = useAppBridge(); // Initialize v4 App Bridge
  const {
    shop: [shop],
    plan: [plan],
    setting: [setting, setSetting],
    originalSetting: [originalSetting],
    contextualBar: [, setContextualBar],
  } = useContext(StoreContext);

  const isPaidPlan =
    plan?.name?.toLowerCase() !== "free" && !hasNoChargeId(shop);

  const handleSubscriptionClick = (e) => {
    if (e) e.preventDefault();
    window.history.pushState({}, "", "/subscription");
    window.dispatchEvent(new PopStateEvent("popstate"));
  };

  // productScope: 'all' | 'include' | 'exclude' (only one allowed per rule)
  const [productScope, setProductScope] = useState(() => {
    const scope = initialData?.product_scope || initialData?.productScope;
    if (scope === "include" || scope === "exclude") return scope;
    return initialData?.is_all === false || initialData?.isAll === false
      ? "include"
      : "all";
  });
  const [name, setName] = useState(
    initialData?.rule_name || initialData?.ruleName || "",
  );
  const [amount, setAmount] = useState(initialData?.amount || "");
  const [amountType, setAmountType] = useState(
    initialData?.amount_type || initialData?.amountType || "percentage",
  );
  const [enableFullPayment, setEnableFullPayment] = useState(
    (initialData?.amount_type || initialData?.amountType) === "percentage" &&
      initialData?.amount == 100,
  );
  const [productIds, setProductIds] = useState(() => {
    const ids = initialData?.product_ids ?? initialData?.productIds;
    if (Array.isArray(ids)) return ids.filter(Boolean).join(",");
    if (typeof ids === "string") return ids;
    return "";
  });
  const [productPickerError, setProductPickerError] = useState(null);
  
  // Variant filter state
  const [variantScope, setVariantScope] = useState(() => {
    const scope = initialData?.variant_scope || initialData?.variantScope;
    if (scope === "include" || scope === "exclude") return scope;
    return "all";
  });
  const [variantIds, setVariantIds] = useState(() => {
    const ids = initialData?.variant_ids ?? initialData?.variantIds;
    if (Array.isArray(ids)) return ids.filter(Boolean).join(",");
    if (typeof ids === "string") return ids;
    return "";
  });
  const [variantPickerError, setVariantPickerError] = useState(null);

  const [collectionScope, setCollectionScope] = useState(() => {
    const scope = initialData?.collection_scope || initialData?.collectionScope;
    if (scope === "include" || scope === "exclude") return scope;
    return "all";
  });
  const [collectionIds, setCollectionIds] = useState(() => {
    const ids = initialData?.collection_ids ?? initialData?.collectionIds;
    if (Array.isArray(ids)) return ids.filter(Boolean).join(",");
    if (typeof ids === "string") return ids;
    return "";
  });
  const [collectionPickerError, setCollectionPickerError] = useState(null);

  // Rule-wide flag: when true, the include-scope checks pass if ANY cart item
  // satisfies the condition; when false, every cart item must satisfy it (existing
  // AND behavior). Applies uniformly to product/variant/collection include scopes.
  const [matchAnyProduct, setMatchAnyProduct] = useState(
    initialData?.match_any_product ?? initialData?.matchAnyProduct ?? false,
  );

  // When enabled on a COD rule, selecting this option in the storefront popup
  // restricts checkout to only the COD shipping + Cash on Delivery payment method.
  const [checkoutCodOnly, setCheckoutCodOnly] = useState(
    initialData?.checkout_cod_only ?? initialData?.checkoutCodOnly ?? false,
  );

  const [enableInTheme, setEnableInTheme] = useState(
    initialData?.isEnabled ?? true,
  );

  const [isDirty, setIsDirty] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const originalDataRef = useRef(initialData);
  const [errors, setErrors] = useState({});
  const [, setErrorTrigger] = useState(false);

  const validateForm = () => {
    const newErrors = {};
    if (!name || name.trim() === "") {
      newErrors.name = I18n.t("partial.error_name_required");
    }
    if (amountType === "cod") {
      if (amount === "" || amount === null) {
        // ✅ blank is allowed for COD
      } else if (isNaN(amount) || Number(amount) < 0) {
        newErrors.amount = I18n.t("partial.error_amount_invalid");
      }
    } else {
      const trimmedAmount = (amount || "").toString().trim();
      if (!trimmedAmount || isNaN(trimmedAmount) || Number(trimmedAmount) < 0) {
        newErrors.amount = I18n.t("partial.error_amount_invalid");
      }
    }
    if (isPaidPlan && (productScope === "include" || productScope === "exclude")) {
      const ids = (productIds || "").split(",").filter(Boolean);
      if (ids.length === 0) {
        newErrors.productIds =
          I18n.t("partial.error_select_at_least_one_product", { defaultValue: "Select at least one product for this rule." });
      }
    }
    if (isPaidPlan && (collectionScope === "include" || collectionScope === "exclude")) {
      const ids = (collectionIds || "").split(",").filter(Boolean);
      if (ids.length === 0) {
        newErrors.collectionIds =
          I18n.t("partial.error_select_at_least_one_collection", { defaultValue: "Select at least one collection for this rule." });
      }
    }
    const itemBounds = [minCartItems, maxCartItems].map((v) => String(v ?? "").trim());
    if (itemBounds.some((v) => v !== "" && !/^\d+$/.test(v))) {
      newErrors.cartItemsRange = I18n.t("partial.error_cart_items_whole_number", {
        defaultValue: "Enter a whole number of items (0 or more).",
      });
    } else if (
      itemBounds[0] !== "" &&
      itemBounds[1] !== "" &&
      Number(itemBounds[1]) < Number(itemBounds[0])
    ) {
      newErrors.cartItemsRange = I18n.t("partial.error_cart_items_max_below_min", {
        defaultValue: "Max cart items must be greater than or equal to min cart items.",
      });
    }
    setErrors(newErrors);
    setErrorTrigger(Object.keys(newErrors).length > 0);
    return Object.keys(newErrors).length === 0;
  };

  const [discountCode, setDiscountCode] = useState(
    initialData?.discountCode || null,
  );
  const [discountValue, setDiscountValue] = useState(
    initialData?.discountValue || "",
  );
  const [discountType, setDiscountType] = useState(
    initialData?.discountType || "fixed",
  );
  const [minCartRange, setMinCartRange] = useState(
    initialData?.minCartRange || "",
  );
  const [maxCartRange, setMaxCartRange] = useState(
    initialData?.maxCartRange || "",
  );
  const [amountToShow, setAmountToShow] = useState(
    initialData?.amountToShow || "",
  );
  // No default: stays null until the merchant sets it either way.
  const [freeDelivery, setFreeDelivery] = useState(
    initialData?.free_delivery ?? initialData?.freeDelivery ?? null,
  );
  const [shippingCharge, setShippingCharge] = useState(() => {
    const raw = initialData?.shippingCharge ?? initialData?.shipping_charge;
    if (raw == null || String(raw).trim() === "") return "";
    const parsed = parseFloat(raw);
    return isNaN(parsed) ? "" : String(parsed);
  });
  const [shippingChargeText, setShippingChargeText] = useState(
    initialData?.shippingChargeText || initialData?.shipping_charge_text || "",
  );
  const shippingInOptionsEnabled =
    setting?.include_shipping_in_payment_options === true ||
    setting?.include_shipping_in_payment_options === "true" ||
    setting?.includeShippingInPaymentOptions === true ||
    setting?.includeShippingInPaymentOptions === "true";
  const [subHeading, setSubHeading] = useState(initialData?.subHeading || "");
  const [customSaveText, setCustomSaveText] = useState(
    initialData?.customSaveText || initialData?.custom_save_text || "",
  );
  const [descriptionTemplate, setDescriptionTemplate] = useState(
    initialData?.descriptionTemplate || initialData?.description_template || "",
  );
  const [zipcodeBlacklistEnabled, setZipcodeBlacklistEnabled] = useState(
    initialData?.zipcodeBlacklistEnabled || initialData?.zipcode_blacklist_enabled || false,
  );
  const [zipcodeBlacklist, setZipcodeBlacklist] = useState(
    initialData?.zipcodeBlacklist || initialData?.zipcode_blacklist || "",
  );
  const [phoneBlacklist, setPhoneBlacklist] = useState(
    (initialData?.phoneBlacklist || initialData?.phone_blacklist || []).join(", "),
  );
  const [emailBlacklist, setEmailBlacklist] = useState(
    (initialData?.emailBlacklist || initialData?.email_blacklist || []).join(", "),
  );
  const [zipcodeWhitelistEnabled, setZipcodeWhitelistEnabled] = useState(
    initialData?.zipcodeWhitelistEnabled || initialData?.zipcode_whitelist_enabled || false,
  );
  const [zipcodeWhitelist, setZipcodeWhitelist] = useState(
    initialData?.zipcodeWhitelist || initialData?.zipcode_whitelist || "",
  );

  // Cart item count gate. Persisted as a jsonb column that stays null until a
  // bound is set; the storefront only waits on cart.js for rules that have one.
  const initialCartItemsRange =
    initialData?.cartItemsRange || initialData?.cart_items_range || null;
  const readCartItemsBound = (snake, camel) => {
    const v = initialCartItemsRange?.[snake] ?? initialCartItemsRange?.[camel];
    return v === null || v === undefined ? "" : String(v);
  };
  const [minCartItems, setMinCartItems] = useState(
    readCartItemsBound("min_cart_items", "minCartItems"),
  );
  const [maxCartItems, setMaxCartItems] = useState(
    readCartItemsBound("max_cart_items", "maxCartItems"),
  );

  // RTO engine gate. Persisted as a single jsonb column that stays null until
  // the merchant turns it on, so an untouched rule is never risk-gated.
  // Repeat customers: both JSON columns stay null until switched on.
  const isPrepaidRule =
    enableFullPayment || (amountType === "percentage" && parseFloat(amount) === 100);
  const initialRepeat =
    initialData?.repeatCustomerDiscount || initialData?.repeat_customer_discount || null;
  const [repeatEnabled, setRepeatEnabled] = useState(!!initialRepeat?.enabled);
  const [repeatType, setRepeatType] = useState(
    initialRepeat?.discount_type || initialRepeat?.discountType || "percentage",
  );
  const [repeatValue, setRepeatValue] = useState(
    String(initialRepeat?.discount_value ?? initialRepeat?.discountValue ?? ""),
  );

  const initialCooling =
    initialData?.codCoolingPeriod || initialData?.cod_cooling_period || null;
  const COOLING_PRESETS = ["7", "8", "15", "30"];
  const [coolingEnabled, setCoolingEnabled] = useState(!!initialCooling?.enabled);
  const [coolingDays, setCoolingDays] = useState(
    initialCooling?.days ? String(initialCooling.days) : "7",
  );
  const [coolingCustom, setCoolingCustom] = useState(
    !!initialCooling?.days && !COOLING_PRESETS.includes(String(initialCooling.days)),
  );

  const initialRtoEngine = initialData?.rtoEngine || initialData?.rto_engine || null;
  const [rtoEngineEnabled, setRtoEngineEnabled] = useState(
    !!(initialRtoEngine && initialRtoEngine.enabled),
  );
  const [rtoHideAtBand, setRtoHideAtBand] = useState(
    initialRtoEngine?.hide_at_band || "high",
  );
  const [rtoMinScore, setRtoMinScore] = useState(
    initialRtoEngine?.min_score !== null && initialRtoEngine?.min_score !== undefined
      ? String(initialRtoEngine.min_score)
      : "",
  );

  // Default templates based on rule type
  const DEFAULT_TEMPLATES = {
    cod: "Pay {{total}} on delivery",
    cod_with_fee: "Pay {{total}} on delivery ({{cod_fee}} COD fee applicable)",
    percentage_100: "Pay {{pay_now}} now (prepaid)",
    percentage_100_with_discount: "Pay {{pay_now}} now and get {{discount}} off",
    percentage: "Pay {{pay_now}} now and {{pay_later}} on delivery",
    fixed: "Pay {{pay_now}} now and {{pay_later}} on delivery",
  };

  // Get the default template based on current rule configuration
  const getDefaultTemplate = useCallback(() => {
    if (amountType === "cod") {
      const codFee = parseFloat(amountToShow || amount || 0);
      return codFee > 0 ? DEFAULT_TEMPLATES.cod_with_fee : DEFAULT_TEMPLATES.cod;
    }
    if (enableFullPayment || (amountType === "percentage" && parseFloat(amount) === 100)) {
      const hasDiscount = discountCode && parseFloat(discountValue) > 0;
      return hasDiscount
        ? DEFAULT_TEMPLATES.percentage_100_with_discount
        : DEFAULT_TEMPLATES.percentage_100;
    }
    if (amountType === "percentage") {
      return DEFAULT_TEMPLATES.percentage;
    }
    return DEFAULT_TEMPLATES.fixed;
  }, [amountType, amount, amountToShow, enableFullPayment, discountCode, discountValue]);

  // Update template when rule type changes (only if template is empty or matches a default)
  useEffect(() => {
    const currentDefault = getDefaultTemplate();
    const isUsingDefault =
      !descriptionTemplate ||
      Object.values(DEFAULT_TEMPLATES).includes(descriptionTemplate);
    if (isUsingDefault && descriptionTemplate !== currentDefault) {
      setDescriptionTemplate(currentDefault);
    }
  }, [amountType, enableFullPayment, amount, amountToShow, discountCode, discountValue]);

  // 2. Refactored Save logic for v4
  const handleSave = useCallback(() => {
    if (!validateForm()) return;
    setIsSaving(true);

    const finalAmount =
      amountType === "cod" && (amount === "" || amount === 0) ? 0 : amount;

    const codFormEnabled =
      setting?.cod_form_enabled === true ||
      setting?.cod_form_enabled === "true" ||
      setting?.codFormEnabled === true ||
      setting?.codFormEnabled === "true";

    const includeShippingInPaymentOptions = shippingInOptionsEnabled;

    const payload = {
      rule_name: name,
      amount: finalAmount,
      amount_type: amountType,
      product_scope: productScope,
      product_ids: productScope === "include" || productScope === "exclude" ? productIds : "",
      is_all: productScope === "all",
      is_enabled: enableInTheme,
      is_cart_rule: true,
      amount_to_show: amountToShow,
      shipping_charge:
        String(shippingCharge).trim() === ""
          ? null
          : Math.max(0, parseFloat(shippingCharge) || 0),
      shipping_charge_text: String(shippingChargeText || "").trim() || null,
      max_cart_range: maxCartRange,
      min_cart_range: minCartRange,
      // null (not {}) when both are blank, so the storefront never waits on
      // cart.js for a rule without an item range.
      cart_items_range:
        String(minCartItems ?? "").trim() === "" && String(maxCartItems ?? "").trim() === ""
          ? null
          : {
              min_cart_items:
                String(minCartItems ?? "").trim() === "" ? null : parseInt(minCartItems, 10),
              max_cart_items:
                String(maxCartItems ?? "").trim() === "" ? null : parseInt(maxCartItems, 10),
            },
      sub_heading: subHeading,
      custom_save_text: String(customSaveText || "").trim() || null,
      discount_code: discountCode ?? "",
      discount_value: discountValue ?? "",
      discount_type: discountType ?? "fixed",
      cod_form_enabled: !!codFormEnabled,
      include_shipping_in_payment_options: !!includeShippingInPaymentOptions,
      description_template: descriptionTemplate ?? "",
      zipcode_blacklist_enabled: !!zipcodeBlacklistEnabled,
      zipcode_blacklist: zipcodeBlacklist ?? "",
      zipcode_whitelist_enabled: !!zipcodeWhitelistEnabled,
      zipcode_whitelist: zipcodeWhitelist ?? "",
      phone_blacklist: phoneBlacklist.split(/[,;\n]/).map((p) => p.trim()).filter(Boolean),
      email_blacklist: emailBlacklist.split(/[,;\n]/).map((e) => e.trim().toLowerCase()).filter(Boolean),
      // Prepaid (100%) rules only; an order-level discount added to the rule's own.
      repeat_customer_discount:
        isPrepaidRule && repeatEnabled
          ? {
              enabled: true,
              discount_type: repeatType,
              discount_value: parseFloat(repeatValue) || 0,
            }
          : null,
      cod_cooling_period:
        amountType === "cod" && coolingEnabled && parseInt(coolingDays, 10) > 0
          ? { enabled: true, days: parseInt(coolingDays, 10) }
          : null,
      // null (not {}) when off, so the column reads as "never configured".
      rto_engine: rtoEngineEnabled
        ? {
            enabled: true,
            hide_at_band: rtoHideAtBand || "high",
            min_score: String(rtoMinScore).trim() === "" ? null : parseInt(rtoMinScore, 10),
          }
        : null,
      variant_scope: variantScope,
      variant_ids: variantScope === "include" || variantScope === "exclude"
        ? (variantIds || "").split(",").filter(Boolean)
        : [],
      collection_scope: collectionScope,
      collection_ids: collectionScope === "include" || collectionScope === "exclude"
        ? (collectionIds || "").split(",").filter(Boolean)
        : [],
      match_any_product: !!matchAnyProduct,
      checkout_cod_only: amountType === "cod" ? !!checkoutCodOnly : false,
      free_delivery: freeDelivery === null ? null : !!freeDelivery,
    };

    const action = initialData
      ? handleUpdate(initialData.id, payload)
      : handleCreate(payload);

    action
      .then((success) => {
        if (success) {
          shopify.toast.show(I18n.t("admin.settings_saved"));
          setIsDirty(false);
          setContextualBar(false);
          onBack();
        }
      })
      .finally(() => {
        setIsSaving(false);
      });
  }, [
    name,
    amount,
    amountType,
    productScope,
    productIds,
    enableInTheme,
    amountToShow,
    shippingCharge,
    shippingChargeText,
    maxCartRange,
    minCartRange,
    minCartItems,
    maxCartItems,
    subHeading,
    customSaveText,
    enableFullPayment,
    discountCode,
    discountValue,
    discountType,
    descriptionTemplate,
    zipcodeBlacklistEnabled,
    zipcodeBlacklist,
    zipcodeWhitelistEnabled,
    zipcodeWhitelist,
    phoneBlacklist,
    emailBlacklist,
    rtoEngineEnabled,
    rtoHideAtBand,
    rtoMinScore,
    repeatEnabled,
    repeatType,
    repeatValue,
    isPrepaidRule,
    coolingEnabled,
    coolingDays,
    variantScope,
    variantIds,
    collectionScope,
    collectionIds,
    matchAnyProduct,
    checkoutCodOnly,
    freeDelivery,
    setting,
    initialData,
    handleUpdate,
    handleCreate,
    shopify,
    onBack,
    setContextualBar,
  ]);

  const handleDiscard = useCallback(() => {
    // Revert global setting (e.g. cod_form_enabled) to original
    if (originalSetting) {
      setSetting(JSON.parse(JSON.stringify(originalSetting)));
    }
    setIsDirty(false);
    setContextualBar(false);
    onBack();
  }, [onBack, setContextualBar, originalSetting, setSetting]);

  const onDataChange = (setter) => (value) => {
    setter(value);
    setIsDirty(true);
    setErrorTrigger(false);
  };

  const openProductPicker = useCallback(async () => {
    if (!isPaidPlan) return;
    const currentIds = (productIds || "").split(",").filter(Boolean);
    const selectionIds = currentIds.map((id) => ({
      id: `gid://shopify/Product/${id}`,
    }));
    try {
      const selected = await shopify.resourcePicker({
        type: "product",
        multiple: true,
        selectionIds,
        action: "select",
      });
      if (selected) {
        // Resource picker returns the final checked set.
        // Replace existing ids instead of merging so unselected products are removed.
        const selectedIds = selected.map((item) => item.id.split("/").pop());
        const newIds = [...new Set(selectedIds)];
        setProductIds(newIds.join(","));
        setIsDirty(true);
        setProductPickerError(null);
      }
    } catch (err) {
      console.error("Product resource picker error:", err);
      setProductPickerError(
        I18n.t("partial.product_picker_error", { defaultValue: "Failed to open product picker." }),
      );
    }
  }, [shopify, productIds, isPaidPlan]);

  const onProductRemove = useCallback(
    (id) => {
      const current = (productIds || "").split(",").filter(Boolean);
      setProductIds(current.filter((x) => x !== id).join(","));
      setIsDirty(true);
    },
    [productIds],
  );

  const openVariantPicker = useCallback(async () => {
    if (!isPaidPlan) return;
    const currentIds = (variantIds || "").split(",").filter(Boolean);
    const selectionIds = currentIds.map((id) => ({
      id: `gid://shopify/ProductVariant/${id}`,
    }));
    try {
      const selected = await shopify.resourcePicker({
        type: "variant",
        multiple: true,
        selectionIds,
        action: "select",
      });
      if (selected) {
        const selectedIds = selected.map((item) => item.id.split("/").pop());
        const newIds = [...new Set(selectedIds)];
        setVariantIds(newIds.join(","));
        setIsDirty(true);
        setVariantPickerError(null);
      }
    } catch (err) {
      console.error("Variant resource picker error:", err);
      setVariantPickerError(
        I18n.t("partial.variant_picker_error", { defaultValue: "Failed to open variant picker." }),
      );
    }
  }, [shopify, variantIds, isPaidPlan]);

  const onVariantRemove = useCallback(
    (id) => {
      const current = (variantIds || "").split(",").filter(Boolean);
      setVariantIds(current.filter((x) => x !== id).join(","));
      setIsDirty(true);
    },
    [variantIds],
  );

  const openCollectionPicker = useCallback(async () => {
    if (!isPaidPlan) return;
    const currentIds = (collectionIds || "").split(",").filter(Boolean);
    const selectionIds = currentIds.map((id) => ({
      id: `gid://shopify/Collection/${id}`,
    }));
    try {
      const selected = await shopify.resourcePicker({
        type: "collection",
        multiple: true,
        selectionIds,
        action: "select",
      });
      if (selected) {
        const selectedIds = selected.map((item) => item.id.split("/").pop());
        const newIds = [...new Set(selectedIds)];
        setCollectionIds(newIds.join(","));
        setIsDirty(true);
        setCollectionPickerError(null);
      }
    } catch (err) {
      console.error("Collection resource picker error:", err);
      setCollectionPickerError(
        I18n.t("partial.collection_picker_error", { defaultValue: "Failed to open collection picker." }),
      );
    }
  }, [shopify, collectionIds, isPaidPlan]);

  const onCollectionRemove = useCallback(
    (id) => {
      const current = (collectionIds || "").split(",").filter(Boolean);
      setCollectionIds(current.filter((x) => x !== id).join(","));
      setIsDirty(true);
    },
    [collectionIds],
  );

  const handleAmountTypeChange = (value) => {
    setIsDirty(true);
    if (value === "full_payment") {
      setEnableFullPayment(true);
      setName(I18n.t("partial.full_payment_label"));
      setAmount(100);
      setAmountType("percentage");
    } else {
      setEnableFullPayment(false);
      setAmountType(value);
      setAmount("");
    }
  };

  // Get dynamic help text based on selected amount type
  const getAmountTypeHelpText = () => {
    const currentType = enableFullPayment ? "full_payment" : amountType;
    switch (currentType) {
      case "percentage":
        return I18n.t("partial.amount_type_help_percentage");
      case "fixed":
        return I18n.t("partial.amount_type_help_fixed");
      case "full_payment":
        return I18n.t("partial.amount_type_help_full_payment");
      case "cod":
        return I18n.t("partial.amount_type_help_cod");
      default:
        return I18n.t("partial.amount_type_help");
    }
  };

  const amountTypeOptions = [
    { label: I18n.t("partial.amount_type_percentage"), value: "percentage" },
    { label: I18n.t("partial.amount_type_fixed"), value: "fixed" },
    {
      label: I18n.t("partial.amount_type_full_payment"),
      value: "full_payment",
    },
    { label: I18n.t("partial.amount_type_cod"), value: "cod" },
  ];

  return (
    <Page
      backAction={{
        content: I18n.t("partial.back"),
        onAction: () => {
          // Shopify-like: when unsaved, back does nothing (no alert, no navigation)
          if (isDirty) return;
          onBack();
        },
      }}
      title={
        initialData ? I18n.t("partial.edit_rule") : I18n.t("partial.add_rule")
      }
      fullWidth
    >
      {/* 3. Declarative Save Bar for v4 */}
      <SaveBar data-save-bar open={isDirty}>
        <button
          variant="primary"
          onClick={handleSave}
          loading={isSaving ? "" : undefined}
          disabled={isSaving}
        >
          {initialData
            ? I18n.t("partial.save_changes")
            : I18n.t("partial.save")}
        </button>
        <button onClick={handleDiscard}>{I18n.t("admin.discard")}</button>
      </SaveBar>

      <Layout>
        <Layout.Section>
          <Box paddingBlockEnd="400">
            <FeatureCallout
              illustration="payments"
              image={PARTIAL_PAYMENT_CALLOUT_IMAGE}
              title={I18n.t("documentation.partial_payment_help_title")}
              description={I18n.t(
                "documentation.partial_payment_help_description",
              )}
              docsUrl="https://codking.notion.site/Step-By-Step-Guide-for-Setting-Up-Upfront-Partial-Payment-Token-Amount-1c96e71a63f98005aaddd04f5ea6000a#1c96e71a63f98005aaddd04f5ea6000a"
              videos={[
                {
                  url: "https://youtu.be/gq2C3A0pbXY?si=sJ5ZfDo4Am_jCX5y",
                  label: I18n.t("documentation_buttons.watch_setup_video"),
                },
                {
                  url: "https://youtu.be/BtB4CVRqwZM?si=X7wiKrfM3vbiiOgR",
                  label: I18n.t("documentation_buttons.partial_payment_demo"),
                },
              ]}
              showChat
            />
          </Box>
          <Box paddingBlock="400" paddingInline="400" background="bg-surface">
            <BlockStack gap={{ xs: "800", sm: "400" }}>
              {/* Rule Configuration Section */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.rule_configuration")}
                    </Text>
                    <Text as="p" variant="bodyMd">
                      {I18n.t("partial.rule_configuration_desc")}
                    </Text>
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <TextField
                      label={I18n.t("partial.rule_name")}
                      value={name ?? ""}
                      onChange={(value) => {
                        setName(value);
                        if (errors.name && value.trim()) {
                          const newErrors = { ...errors };
                          delete newErrors.name;
                          setErrors(newErrors);
                        }
                        setIsDirty(true);
                        setErrorTrigger(false);
                      }}
                      error={errors.name}
                      autoComplete="off"
                    />
                    <Select
                      label={I18n.t("partial.amount_type")}
                      options={amountTypeOptions}
                      value={enableFullPayment ? "full_payment" : amountType}
                      onChange={handleAmountTypeChange}
                      helpText={getAmountTypeHelpText()}
                      disabled={!!initialData}
                    />
                    {!enableFullPayment && (
                      <TextField
                        label={
                          amountType === "cod"
                            ? I18n.t("partial.cod_charge_label")
                            : I18n.t("partial.amount_label")
                        }
                        value={amount ?? ""}
                        onChange={(value) => {
                          setAmount(value);
                          if (
                            errors.amount &&
                            value &&
                            !isNaN(value) &&
                            Number(value) > 0
                          ) {
                            const newErrors = { ...errors };
                            delete newErrors.amount;
                            setErrors(newErrors);
                          }
                          setIsDirty(true);
                          setErrorTrigger(false);
                        }}
                        error={errors.amount}
                        type="number"
                        suffix={amountType === "percentage" ? "%" : ""}
                        autoComplete="off"
                        helpText={
                          amountType === "cod"
                            ? I18n.t("partial.cod_charge_help")
                            : ""
                        }
                      />
                    )}
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              {/* RTO Engine (Advanced) */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      RTO Engine (Advanced)
                    </Text>
                    {!isPaidPlan && (
                      <Banner tone="warning" onDismiss={() => {}}>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodyMd">
                            {I18n.t("partial.advanced_paid_plan_only")}{" "}
                            <Link onClick={handleSubscriptionClick} url="#">
                              {I18n.t("partial.upgrade_to_access")}
                            </Link>
                          </Text>
                        </BlockStack>
                      </Banner>
                    )}
                    {isPaidPlan && (
                      <Text as="p" variant="bodyMd">
                        Hide this payment rule for customers whose phone number and
                        pincode score as high RTO risk. Scored after OTP verification,
                        just before payment options are shown.
                      </Text>
                    )}
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <Checkbox
                      label="Enable RTO risk check"
                      helpText={
                        isPaidPlan
                          ? "When enabled, this rule is hidden for shoppers scored above the threshold below. Left off, the rule is never risk-gated."
                          : undefined
                      }
                      checked={rtoEngineEnabled}
                      onChange={(checked) => {
                        setRtoEngineEnabled(checked);
                        setIsDirty(true);
                      }}
                      disabled={!isPaidPlan}
                    />
                    {rtoEngineEnabled && isPaidPlan && (
                      <BlockStack gap="300">
                        <Select
                          label="Hide this rule at risk band"
                          options={[
                            { label: "High risk only", value: "high" },
                            { label: "Medium risk and above", value: "medium" },
                          ]}
                          value={rtoHideAtBand}
                          onChange={(value) => {
                            setRtoHideAtBand(value);
                            setIsDirty(true);
                          }}
                          helpText="High is the stricter cutoff (score 60+). Medium hides the rule from score 30 up."
                          disabled={!isPaidPlan}
                        />
                        <TextField
                          label="Or hide above risk score (optional)"
                          type="number"
                          min={0}
                          max={100}
                          value={rtoMinScore ?? ""}
                          onChange={(value) => {
                            setRtoMinScore(value);
                            setIsDirty(true);
                          }}
                          autoComplete="off"
                          placeholder="60"
                          helpText="0-100. Applied in addition to the band above - whichever triggers first hides the rule. Leave blank to use the band alone."
                          disabled={!isPaidPlan}
                        />
                        <Box
                          background="bg-surface-secondary"
                          padding="300"
                          borderRadius="200"
                        >
                          <BlockStack gap="200">
                            <Text as="p" variant="bodySm" fontWeight="semibold">
                              How scoring works:
                            </Text>
                            <BlockStack gap="100">
                              <Text as="p" variant="bodySm">
                                Risk combines the shopper's own COD/RTO history with the
                                delivery pincode's history, so a new customer in a clean
                                pincode scores low.
                              </Text>
                              <Text as="p" variant="bodySm">
                                If scoring is slow or unavailable the rule stays visible,
                                so a backend issue never removes COD for everyone.
                              </Text>
                            </BlockStack>
                          </BlockStack>
                        </Box>
                      </BlockStack>
                    )}
                  </BlockStack>
                </Card>
              </InlineGrid>

              {/* Complete COD payment there itself (only when amount type is COD; paid plans only) */}
              {amountType === "cod" && (
                <>
                  <Divider />
                  <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                    <Box
                      as="section"
                      paddingInlineStart={{ xs: 400, sm: 0 }}
                      paddingInlineEnd={{ xs: 400, sm: 0 }}
                    >
                      <BlockStack gap="400">
                        <Text as="h3" variant="headingMd">
                          {I18n.t("partial.cod_form_enabled_label")}
                        </Text>
                        {!isPaidPlan && (
                          <Banner tone="warning" onDismiss={() => {}}>
                            <BlockStack gap="200">
                              <Text as="p" variant="bodyMd">
                                {I18n.t("partial.cod_form_enabled_paid_only")}{" "}
                                <Link onClick={handleSubscriptionClick} url="#">
                                  {I18n.t("partial.upgrade_to_access")}
                                </Link>
                              </Text>
                            </BlockStack>
                          </Banner>
                        )}
                        {isPaidPlan && (
                          <Text as="p" variant="bodyMd" tone="subdued">
                            {I18n.t("partial.cod_form_enabled_help")}
                          </Text>
                        )}
                      </BlockStack>
                    </Box>
                    <Card roundedAbove="sm">
                      <BlockStack gap="400">
                        <Checkbox
                          label={I18n.t("partial.cod_form_enabled_label")}
                          helpText={
                            isPaidPlan
                              ? I18n.t("partial.cod_form_enabled_help")
                              : undefined
                          }
                          checked={
                            setting?.cod_form_enabled === true ||
                            setting?.cod_form_enabled === "true" ||
                            setting?.codFormEnabled === true ||
                            setting?.codFormEnabled === "true"
                          }
                          onChange={(checked) => {
                            const updated = {
                              ...setting,
                              cod_form_enabled: checked,
                              codFormEnabled: checked,
                            };
                            setSetting(updated);
                            setIsDirty(true);
                            setContextualBar(true);
                          }}
                          disabled={!isPaidPlan}
                        />
                        <Checkbox
                          label={I18n.t("partial.checkout_cod_only_label")}
                          helpText={I18n.t("partial.checkout_cod_only_help")}
                          checked={!!checkoutCodOnly}
                          onChange={(checked) => {
                            setCheckoutCodOnly(checked);
                            setIsDirty(true);
                            setContextualBar(true);
                          }}
                        />
                        <Checkbox
                          label={I18n.t("partial.cod_cooling_label", {
                            defaultValue: "Cooling period for returning customers",
                          })}
                          helpText={I18n.t("partial.cod_cooling_help", {
                            defaultValue:
                              "Hide Cash on Delivery from a returning customer until this many days after their last order. Checked after OTP verification.",
                          })}
                          checked={coolingEnabled}
                          onChange={(checked) => {
                            setCoolingEnabled(checked);
                            setIsDirty(true);
                          }}
                        />
                        {coolingEnabled && (
                          <InlineStack gap="300" blockAlign="end" wrap>
                            <Select
                              label={I18n.t("partial.cod_cooling_days", {
                                defaultValue: "Cooling period",
                              })}
                              options={[
                                ...COOLING_PRESETS.map((d) => ({
                                  label: I18n.t("partial.cod_cooling_n_days", {
                                    count: d,
                                    defaultValue: `${d} days`,
                                  }),
                                  value: d,
                                })),
                                {
                                  label: I18n.t("partial.cod_cooling_custom", {
                                    defaultValue: "Custom",
                                  }),
                                  value: "custom",
                                },
                              ]}
                              value={coolingCustom ? "custom" : coolingDays}
                              onChange={(value) => {
                                if (value === "custom") {
                                  setCoolingCustom(true);
                                } else {
                                  setCoolingCustom(false);
                                  setCoolingDays(value);
                                }
                                setIsDirty(true);
                              }}
                            />
                            {coolingCustom && (
                              <TextField
                                label={I18n.t("partial.cod_cooling_custom_days", {
                                  defaultValue: "Days",
                                })}
                                type="number"
                                min={1}
                                value={coolingDays}
                                onChange={(value) => {
                                  setCoolingDays(value);
                                  setIsDirty(true);
                                }}
                                autoComplete="off"
                              />
                            )}
                          </InlineStack>
                        )}
                      </BlockStack>
                    </Card>
                  </InlineGrid>
                </>
              )}

              <Divider />

              {/* Shipping charges on payment options — shop-level, applies to every rule */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.include_shipping_in_options_label")}
                    </Text>
                    <Text as="p" variant="bodyMd" tone="subdued">
                      {I18n.t("partial.include_shipping_in_options_desc")}
                    </Text>
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <Checkbox
                      label={I18n.t("partial.include_shipping_in_options_label")}
                      helpText={I18n.t(
                        "partial.include_shipping_in_options_help",
                      )}
                      checked={shippingInOptionsEnabled}
                      onChange={(checked) => {
                        const updated = {
                          ...setting,
                          include_shipping_in_payment_options: checked,
                          includeShippingInPaymentOptions: checked,
                        };
                        setSetting(updated);
                        setIsDirty(true);
                        setContextualBar(true);
                      }}
                    />
                    <TextField
                      label={I18n.t("partial.shipping_charge_label")}
                      helpText={I18n.t("partial.shipping_charge_help")}
                      value={shippingCharge}
                      onChange={(value) => {
                        setShippingCharge(value);
                        setIsDirty(true);
                        setErrorTrigger(false);
                      }}
                      type="number"
                      min="0"
                      autoComplete="off"
                      placeholder={I18n.t(
                        "partial.shipping_charge_placeholder",
                      )}
                      disabled={!shippingInOptionsEnabled}
                    />
                    <TextField
                      label={I18n.t("partial.shipping_charge_text_label", {
                        defaultValue: "Shipping charge text",
                      })}
                      helpText={I18n.t("partial.shipping_charge_text_help", {
                        defaultValue:
                          "Replaces the +{{amount}} Shipping badge on this payment option. {{amount}} fills in with the charge. Leave blank to use the default.",
                        amount: "{{amount}}",
                      })}
                      value={shippingChargeText}
                      onChange={(value) => {
                        setShippingChargeText(value);
                        setIsDirty(true);
                      }}
                      autoComplete="off"
                      placeholder={I18n.t("partial.shipping_charge_text_placeholder", {
                        defaultValue: "e.g. +{{amount}} COD fee",
                        amount: "{{amount}}",
                      })}
                      disabled={!shippingInOptionsEnabled}
                    />
                    <Checkbox
                      label={I18n.t("partial.free_delivery_label", {
                        defaultValue: "Offer free delivery on this option",
                      })}
                      helpText={I18n.t("partial.free_delivery_help", {
                        defaultValue:
                          "Shows a green Free Delivery badge on this payment option in the popup.",
                      })}
                      checked={!!freeDelivery}
                      onChange={(checked) => {
                        setFreeDelivery(checked);
                        setIsDirty(true);
                      }}
                    />
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              {/* Cart Range (Advanced) */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.cart_range")}
                    </Text>
                    {!isPaidPlan && (
                      <Banner tone="warning" onDismiss={() => {}}>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodyMd">
                            {I18n.t("partial.advanced_paid_plan_only")}{" "}
                            <Link onClick={handleSubscriptionClick} url="#">
                              {I18n.t("partial.upgrade_to_access")}
                            </Link>
                          </Text>
                        </BlockStack>
                      </Banner>
                    )}
                    {isPaidPlan && (
                      <Text as="p" variant="bodyMd">
                        {I18n.t("partial.cart_range_desc")}
                      </Text>
                    )}
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <InlineStack gap="400">
                      <TextField
                        label={I18n.t("partial.min_cart_range")}
                        value={minCartRange ?? ""}
                        onChange={(value) => {
                          setMinCartRange(value);
                          setIsDirty(true);
                          setErrorTrigger(false);
                        }}
                        autoComplete="off"
                        type="number"
                        disabled={!isPaidPlan}
                      />
                      <TextField
                        label={I18n.t("partial.max_cart_range")}
                        value={maxCartRange ?? ""}
                        onChange={(value) => {
                          setMaxCartRange(value);
                          setIsDirty(true);
                          setErrorTrigger(false);
                        }}
                        autoComplete="off"
                        type="number"
                        disabled={!isPaidPlan}
                      />
                    </InlineStack>
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              {/* Cart Items (Advanced) */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.cart_items_range")}
                    </Text>
                    {isPaidPlan && (
                      <Text as="p" variant="bodyMd">
                        {I18n.t("partial.cart_items_range_desc")}
                      </Text>
                    )}
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <InlineStack gap="400">
                      <TextField
                        label={I18n.t("partial.min_cart_items")}
                        value={minCartItems}
                        onChange={(value) => {
                          setMinCartItems(value);
                          setIsDirty(true);
                          setErrorTrigger(false);
                        }}
                        autoComplete="off"
                        type="number"
                        min={0}
                        step={1}
                        disabled={!isPaidPlan}
                        error={Boolean(errors.cartItemsRange)}
                      />
                      <TextField
                        label={I18n.t("partial.max_cart_items")}
                        value={maxCartItems}
                        onChange={(value) => {
                          setMaxCartItems(value);
                          setIsDirty(true);
                          setErrorTrigger(false);
                        }}
                        autoComplete="off"
                        type="number"
                        min={0}
                        step={1}
                        disabled={!isPaidPlan}
                        error={Boolean(errors.cartItemsRange)}
                      />
                    </InlineStack>
                    {errors.cartItemsRange && (
                      <InlineError
                        message={errors.cartItemsRange}
                        fieldID="cart-items-range"
                      />
                    )}
                    <Text as="p" variant="bodySm" tone="subdued">
                      {I18n.t("partial.cart_items_range_buy_now_note")}
                    </Text>
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              {/* Discount Settings (Advanced) */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.discount_settings_advanced")}
                    </Text>
                    {!isPaidPlan && (
                      <Banner tone="warning" onDismiss={() => {}}>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodyMd">
                            {I18n.t("partial.advanced_paid_plan_only")}{" "}
                            <Link onClick={handleSubscriptionClick} url="#">
                              {I18n.t("partial.upgrade_to_access")}
                            </Link>
                          </Text>
                        </BlockStack>
                      </Banner>
                    )}
                    <BlockStack gap="300">
                      <Text as="p" variant="bodyMd">
                        {I18n.t("partial.discount_settings_desc")}
                      </Text>
                      {isPaidPlan && (
                        <Box
                          background="bg-surface-caution"
                          padding="300"
                          borderRadius="200"
                        >
                          <BlockStack gap="200">
                            <Text as="h4" variant="headingSm" tone="caution">
                              {I18n.t("partial.discount_important_notes_title")}
                            </Text>
                            <BlockStack gap="100">
                              <Text as="p" variant="bodySm">
                                • {I18n.t("partial.discount_important_note_auto")}
                              </Text>
                              <Text as="p" variant="bodySm">
                                • {I18n.t("partial.discount_important_note_test")}
                              </Text>
                            </BlockStack>
                          </BlockStack>
                        </Box>
                      )}
                    </BlockStack>
                  </BlockStack>
                </Box>

                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <TextField
                      label={I18n.t("partial.discount_code")}
                      value={discountCode ?? ""}
                      onChange={(value) => {
                        setDiscountCode(value);
                        setIsDirty(true);
                        setErrorTrigger(false);
                      }}
                      autoComplete="off"
                      disabled={!isPaidPlan}
                    />
                    <Select
                      label={I18n.t("partial.discount_type")}
                      options={[
                        {
                          label: I18n.t("partial.discount_type_fixed"),
                          value: "fixed",
                        },
                        {
                          label: I18n.t("partial.discount_type_percentage"),
                          value: "percentage",
                        },
                      ]}
                      value={discountType}
                      onChange={(value) => {
                        setDiscountType(value);
                        setIsDirty(true);
                      }}
                      disabled={!isPaidPlan}
                    />
                    <TextField
                      label={I18n.t("partial.discount_value")}
                      value={discountValue ?? ""}
                      onChange={(value) => {
                        setDiscountValue(value);
                        setIsDirty(true);
                        setErrorTrigger(false);
                      }}
                      type="number"
                      autoComplete="off"
                      disabled={!isPaidPlan}
                    />
                  </BlockStack>
                </Card>
              </InlineGrid>

              {isPrepaidRule && (
                <>
                  <Divider />

                  {/* Repeat customer discount (prepaid rules) */}
                  <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                    <Box
                      as="section"
                      paddingInlineStart={{ xs: 400, sm: 0 }}
                      paddingInlineEnd={{ xs: 400, sm: 0 }}
                    >
                      <BlockStack gap="400">
                        <Text as="h3" variant="headingMd">
                          {I18n.t("partial.repeat_discount_title", {
                            defaultValue: "Extra discount for returning customers",
                          })}
                        </Text>
                        <Text as="p" variant="bodyMd" tone="subdued">
                          {I18n.t("partial.repeat_discount_desc", {
                            defaultValue:
                              "Customers who have ordered before get this on top of this prepaid rule's discount, applied to the whole order.",
                          })}
                        </Text>
                      </BlockStack>
                    </Box>
                    <Card roundedAbove="sm">
                      <BlockStack gap="400">
                        <Checkbox
                          label={I18n.t("partial.repeat_discount_enable", {
                            defaultValue: "Give returning customers an extra discount",
                          })}
                          checked={repeatEnabled}
                          onChange={(checked) => {
                            setRepeatEnabled(checked);
                            setIsDirty(true);
                          }}
                          disabled={!isPaidPlan}
                        />
                        {repeatEnabled && (
                          <>
                            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="300">
                              <Select
                                label={I18n.t("partial.discount_type")}
                                options={[
                                  { label: I18n.t("partial.discount_type_percentage"), value: "percentage" },
                                  { label: I18n.t("partial.discount_type_fixed"), value: "fixed" },
                                ]}
                                value={repeatType}
                                onChange={(value) => {
                                  setRepeatType(value);
                                  setIsDirty(true);
                                }}
                                disabled={!isPaidPlan}
                              />
                              <TextField
                                label={I18n.t("partial.discount_value")}
                                type="number"
                                min={0}
                                value={repeatValue}
                                onChange={(value) => {
                                  setRepeatValue(value);
                                  setIsDirty(true);
                                }}
                                autoComplete="off"
                                disabled={!isPaidPlan}
                              />
                            </InlineGrid>
                          </>
                        )}
                      </BlockStack>
                    </Card>
                  </InlineGrid>
                </>
              )}

              <Divider />

              {/* Product filter (Advanced) */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.product_filter_heading")}
                    </Text>
                    {!isPaidPlan && (
                      <Banner tone="warning" onDismiss={() => {}}>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodyMd">
                            {I18n.t("partial.advanced_paid_plan_only")}{" "}
                            <Link onClick={handleSubscriptionClick} url="#">
                              {I18n.t("partial.upgrade_to_access")}
                            </Link>
                          </Text>
                        </BlockStack>
                      </Banner>
                    )}
                    {isPaidPlan && (
                      <Text as="p" variant="bodyMd">
                        {I18n.t("partial.product_filter_desc")}
                      </Text>
                    )}
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <ChoiceList
                      title={I18n.t("partial.apply_to_products")}
                      choices={[
                        {
                          label: I18n.t("partial.apply_to_all_products"),
                          value: "all",
                        },
                        {
                          label: I18n.t("partial.apply_to_selected_products"),
                          value: "include",
                        },
                        {
                          label: I18n.t("partial.apply_to_excluded_products"),
                          value: "exclude",
                        },
                      ]}
                      selected={[productScope]}
                      onChange={(value) => {
                        const next = value?.[0] || "all";
                        setProductScope(next);
                        setIsDirty(true);
                      }}
                      disabled={!isPaidPlan}
                    />
                    {(productScope === "include" || productScope === "exclude") && isPaidPlan && (
                      <BlockStack gap="300">
                        {errors.productIds && (
                          <Text as="p" variant="bodySm" tone="critical">
                            {errors.productIds}
                          </Text>
                        )}
                        <Button onClick={openProductPicker}>
                          {productScope === "exclude"
                            ? I18n.t("partial.select_products_to_exclude")
                            : I18n.t("partial.select_products_for_rule")}
                        </Button>
                        {productPickerError && (
                          <Text as="p" variant="bodySm" tone="critical">
                            {productPickerError}
                          </Text>
                        )}
                        {(productIds || "").split(",").filter(Boolean).length >
                        0 ? (
                          <BlockStack gap="200">
                            <Text as="p" variant="bodySm" fontWeight="semibold">
                              {productScope === "exclude"
                                ? I18n.t("partial.excluded_products")
                                : I18n.t("partial.selected_products")}
                            </Text>
                            <BlockStack gap="100">
                              {(productIds || "")
                                .split(",")
                                .filter(Boolean)
                                .map((id) => (
                                  <div
                                    key={id}
                                    style={{
                                      background: "#F6F6F7",
                                      borderRadius: "6px",
                                      padding: "6px 8px",
                                      display: "flex",
                                      justifyContent: "space-between",
                                      alignItems: "center",
                                    }}
                                  >
                                    <span>{id}</span>
                                    <Button
                                      plain
                                      onClick={() => onProductRemove(id)}
                                    >
                                      {I18n.t("add_partial_payment_options.remove")}
                                    </Button>
                                  </div>
                                ))}
                            </BlockStack>
                          </BlockStack>
                        ) : (
                          <Text as="p" variant="bodySm" tone="subdued">
                            {I18n.t("partial.no_products_selected")}
                          </Text>
                        )}
                      </BlockStack>
                    )}
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              {/* Variant filter (Advanced) */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.variant_filter_heading", { defaultValue: "Variant Filter (Advanced)" })}
                    </Text>
                    {!isPaidPlan && (
                      <Banner tone="warning" onDismiss={() => {}}>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodyMd">
                            {I18n.t("partial.advanced_paid_plan_only")}{" "}
                            <Link onClick={handleSubscriptionClick} url="#">
                              {I18n.t("partial.upgrade_to_access")}
                            </Link>
                          </Text>
                        </BlockStack>
                      </Banner>
                    )}
                    {isPaidPlan && (
                      <Text as="p" variant="bodyMd">
                        {I18n.t("partial.variant_filter_desc", { defaultValue: "Filter this rule by specific product variants. Works alongside product filter (AND logic)." })}
                      </Text>
                    )}
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <ChoiceList
                      title={I18n.t("partial.apply_to_variants", { defaultValue: "Apply rule to variants" })}
                      choices={[
                        {
                          label: I18n.t("partial.apply_to_all_variants", { defaultValue: "All variants" }),
                          value: "all",
                        },
                        {
                          label: I18n.t("partial.apply_to_selected_variants", { defaultValue: "Selected variants only" }),
                          value: "include",
                        },
                        {
                          label: I18n.t("partial.apply_to_excluded_variants", { defaultValue: "Exclude selected variants" }),
                          value: "exclude",
                        },
                      ]}
                      selected={[variantScope]}
                      onChange={(value) => {
                        const next = value?.[0] || "all";
                        setVariantScope(next);
                        setIsDirty(true);
                      }}
                      disabled={!isPaidPlan}
                    />
                    {(variantScope === "include" || variantScope === "exclude") && isPaidPlan && (
                      <BlockStack gap="300">
                        <Button onClick={openVariantPicker}>
                          {variantScope === "exclude"
                            ? I18n.t("partial.select_variants_to_exclude", { defaultValue: "Select variants to exclude" })
                            : I18n.t("partial.select_variants_for_rule", { defaultValue: "Select variants" })}
                        </Button>
                        {variantPickerError && (
                          <Text as="p" variant="bodySm" tone="critical">
                            {variantPickerError}
                          </Text>
                        )}
                        {(variantIds || "").split(",").filter(Boolean).length >
                        0 ? (
                          <BlockStack gap="200">
                            <Text as="p" variant="bodySm" fontWeight="semibold">
                              {variantScope === "exclude"
                                ? I18n.t("partial.excluded_variants", { defaultValue: "Excluded variant IDs" })
                                : I18n.t("partial.selected_variants", { defaultValue: "Selected variant IDs" })}
                            </Text>
                            <BlockStack gap="100">
                              {(variantIds || "")
                                .split(",")
                                .filter(Boolean)
                                .map((id) => (
                                  <div
                                    key={id}
                                    style={{
                                      background: "#F6F6F7",
                                      borderRadius: "6px",
                                      padding: "6px 8px",
                                      display: "flex",
                                      justifyContent: "space-between",
                                      alignItems: "center",
                                    }}
                                  >
                                    <span>{id}</span>
                                    <Button
                                      plain
                                      onClick={() => onVariantRemove(id)}
                                    >
                                      {I18n.t("add_partial_payment_options.remove")}
                                    </Button>
                                  </div>
                                ))}
                            </BlockStack>
                          </BlockStack>
                        ) : (
                          <Text as="p" variant="bodySm" tone="subdued">
                            {I18n.t("partial.no_variants_selected", { defaultValue: "No variants selected. Click \"Select variants\" to choose variants for this rule." })}
                          </Text>
                        )}
                      </BlockStack>
                    )}
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.collection_filter_heading", { defaultValue: "Collection Filter (Advanced)" })}
                    </Text>
                    {!isPaidPlan && (
                      <Banner tone="warning" onDismiss={() => {}}>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodyMd">
                            {I18n.t("partial.advanced_paid_plan_only")}{" "}
                            <Link onClick={handleSubscriptionClick} url="#">
                              {I18n.t("partial.upgrade_to_access")}
                            </Link>
                          </Text>
                        </BlockStack>
                      </Banner>
                    )}
                    {isPaidPlan && (
                      <Text as="p" variant="bodyMd">
                        {I18n.t("partial.collection_filter_desc", { defaultValue: "Filter this rule by Shopify collections. Rule applies only when cart products belong to the selected collections." })}
                      </Text>
                    )}
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <ChoiceList
                      title={I18n.t("partial.apply_to_collections", { defaultValue: "Apply rule to collections" })}
                      choices={[
                        {
                          label: I18n.t("partial.apply_to_all_collections", { defaultValue: "All collections" }),
                          value: "all",
                        },
                        {
                          label: I18n.t("partial.apply_to_selected_collections", { defaultValue: "Selected collections only" }),
                          value: "include",
                        },
                        {
                          label: I18n.t("partial.apply_to_excluded_collections", { defaultValue: "Exclude selected collections" }),
                          value: "exclude",
                        },
                      ]}
                      selected={[collectionScope]}
                      onChange={(value) => {
                        const next = value?.[0] || "all";
                        setCollectionScope(next);
                        setIsDirty(true);
                      }}
                      disabled={!isPaidPlan}
                    />
                    {(collectionScope === "include" || collectionScope === "exclude") && isPaidPlan && (
                      <BlockStack gap="300">
                        <Button onClick={openCollectionPicker}>
                          {collectionScope === "exclude"
                            ? I18n.t("partial.select_collections_to_exclude", { defaultValue: "Select collections to exclude" })
                            : I18n.t("partial.select_collections_for_rule", { defaultValue: "Select collections" })}
                        </Button>
                        {collectionPickerError && (
                          <Text as="p" variant="bodySm" tone="critical">
                            {collectionPickerError}
                          </Text>
                        )}
                        {errors.collectionIds && (
                          <Text as="p" variant="bodySm" tone="critical">
                            {errors.collectionIds}
                          </Text>
                        )}
                        {(collectionIds || "").split(",").filter(Boolean).length > 0 ? (
                          <BlockStack gap="200">
                            <Text as="p" variant="bodySm" fontWeight="semibold">
                              {collectionScope === "exclude"
                                ? I18n.t("partial.excluded_collections", { defaultValue: "Excluded collection IDs" })
                                : I18n.t("partial.selected_collections", { defaultValue: "Selected collection IDs" })}
                            </Text>
                            <BlockStack gap="100">
                              {(collectionIds || "")
                                .split(",")
                                .filter(Boolean)
                                .map((id) => (
                                  <div
                                    key={id}
                                    style={{
                                      background: "#F6F6F7",
                                      borderRadius: "6px",
                                      padding: "6px 8px",
                                      display: "flex",
                                      justifyContent: "space-between",
                                      alignItems: "center",
                                    }}
                                  >
                                    <span>{id}</span>
                                    <Button
                                      plain
                                      onClick={() => onCollectionRemove(id)}
                                    >
                                      {I18n.t("add_partial_payment_options.remove")}
                                    </Button>
                                  </div>
                                ))}
                            </BlockStack>
                          </BlockStack>
                        ) : (
                          <Text as="p" variant="bodySm" tone="subdued">
                            {I18n.t("partial.no_collections_selected", { defaultValue: "No collections selected. Click \"Select collections\" to choose collections for this rule." })}
                          </Text>
                        )}
                      </BlockStack>
                    )}
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              {/* Match-any-product (rule-wide toggle) */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("add_partial_payment_options.match_any_product_in_cart")}
                    </Text>
                    <Text as="p" variant="bodyMd">
                      {I18n.t("add_partial_payment_options.when_enabled_this_rule_is_eligible")}
                    </Text>
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <Checkbox
                      label={I18n.t("add_partial_payment_options.show_this_rule_if_any_product")}
                      helpText={I18n.t("add_partial_payment_options.applies_to_product_variant_and_collection")}
                      checked={matchAnyProduct}
                      onChange={(checked) => {
                        setMatchAnyProduct(checked);
                        setIsDirty(true);
                      }}
                    />
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              {/* Zipcode Blacklist (Advanced) */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.zipcode_blacklist_heading", { defaultValue: "Zipcode Restrictions (Advanced)" })}
                    </Text>
                    {!isPaidPlan && (
                      <Banner tone="warning" onDismiss={() => {}}>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodyMd">
                            {I18n.t("partial.advanced_paid_plan_only")}{" "}
                            <Link onClick={handleSubscriptionClick} url="#">
                              {I18n.t("partial.upgrade_to_access")}
                            </Link>
                          </Text>
                        </BlockStack>
                      </Banner>
                    )}
                    {isPaidPlan && (
                      <Text as="p" variant="bodyMd">
                        {I18n.t("partial.zipcode_blacklist_desc", { defaultValue: "Hide this payment rule for specific zipcodes. This only works when address collection is enabled." })}
                      </Text>
                    )}
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <Checkbox
                      label={I18n.t("partial.zipcode_blacklist_enable", { defaultValue: "Enable zipcode restrictions" })}
                      helpText={
                        isPaidPlan
                          ? I18n.t("partial.zipcode_blacklist_enable_help", { defaultValue: "When enabled, this rule will be hidden for customers with the specified zipcodes" })
                          : undefined
                      }
                      checked={zipcodeBlacklistEnabled}
                      onChange={(checked) => {
                        setZipcodeBlacklistEnabled(checked);
                        setIsDirty(true);
                      }}
                      disabled={!isPaidPlan}
                    />
                    {zipcodeBlacklistEnabled && isPaidPlan && (
                      <BlockStack gap="300">
                        <TextField
                          label={I18n.t("partial.zipcode_blacklist_label", { defaultValue: "Zipcodes to hide this rule" })}
                          value={zipcodeBlacklist ?? ""}
                          onChange={(value) => {
                            setZipcodeBlacklist(value);
                            setIsDirty(true);
                          }}
                          autoComplete="off"
                          multiline={3}
                          placeholder="110001, 110002, 400001-400010"
                          helpText={I18n.t("partial.zipcode_blacklist_help", { defaultValue: "Enter zipcodes separated by commas. Supports ranges (e.g., 400001-400010)." })}
                          disabled={!isPaidPlan}
                        />
                        <Box
                          background="bg-surface-secondary"
                          padding="300"
                          borderRadius="200"
                        >
                          <BlockStack gap="200">
                            <Text as="p" variant="bodySm" fontWeight="semibold">
                              {I18n.t("partial.zipcode_examples_title", { defaultValue: "Examples:" })}
                            </Text>
                            <BlockStack gap="100">
                              <Text as="p" variant="bodySm">
                                <code>110001, 110002, 110003</code> - {I18n.t("partial.zipcode_example_individual", { defaultValue: "Individual zipcodes" })}
                              </Text>
                              <Text as="p" variant="bodySm">
                                <code>400001-400099</code> - {I18n.t("partial.zipcode_example_range", { defaultValue: "Zipcode range (all from 400001 to 400099)" })}
                              </Text>
                              <Text as="p" variant="bodySm">
                                <code>110001, 400001-400010, 560001</code> - {I18n.t("partial.zipcode_example_mixed", { defaultValue: "Mixed: individual + ranges" })}
                              </Text>
                            </BlockStack>
                          </BlockStack>
                        </Box>
                      </BlockStack>
                    )}
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              {/* Phone Blacklist (Advanced) */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.phone_blacklist_heading", { defaultValue: "Phone & Email Restrictions (Advanced)" })}
                    </Text>
                    {!isPaidPlan && (
                      <Banner tone="warning" onDismiss={() => {}}>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodyMd">
                            {I18n.t("partial.advanced_paid_plan_only")}{" "}
                            <Link onClick={handleSubscriptionClick} url="#">
                              {I18n.t("partial.upgrade_to_access")}
                            </Link>
                          </Text>
                        </BlockStack>
                      </Banner>
                    )}
                    {isPaidPlan && (
                      <Text as="p" variant="bodyMd">
                        {I18n.t("partial.phone_blacklist_desc", { defaultValue: "Hide this payment rule for specific phone numbers or emails. Uses the phone and email the customer entered for OTP or in their address." })}
                      </Text>
                    )}
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <TextField
                      label={I18n.t("partial.phone_blacklist_label", { defaultValue: "Phone numbers to hide this rule" })}
                      value={phoneBlacklist}
                      onChange={(value) => {
                        setPhoneBlacklist(value);
                        setIsDirty(true);
                      }}
                      autoComplete="off"
                      multiline={3}
                      placeholder="9876543210, +91 91234 56789"
                      helpText={I18n.t("partial.phone_blacklist_help", { defaultValue: "Enter phone numbers separated by commas or new lines. Spaces, dashes, + and the country code are ignored (e.g., +91 98765 43210 matches 9876543210)." })}
                      disabled={!isPaidPlan}
                    />
                    <TextField
                      label={I18n.t("partial.email_blacklist_label", { defaultValue: "Emails to hide this rule" })}
                      value={emailBlacklist}
                      onChange={(value) => {
                        setEmailBlacklist(value);
                        setIsDirty(true);
                      }}
                      autoComplete="off"
                      multiline={3}
                      placeholder="john@example.com, test@test.com"
                      helpText={I18n.t("partial.email_blacklist_help", { defaultValue: "Enter emails separated by commas or new lines. Matching ignores upper/lower case and extra spaces." })}
                      disabled={!isPaidPlan}
                    />
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("add_partial_payment_options.zipcode_includes_advanced")}
                    </Text>
                    {!isPaidPlan && (
                      <Banner tone="warning" onDismiss={() => {}}>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodyMd">
                            {I18n.t("partial.advanced_paid_plan_only")}{" "}
                            <Link onClick={handleSubscriptionClick} url="#">
                              {I18n.t("partial.upgrade_to_access")}
                            </Link>
                          </Text>
                        </BlockStack>
                      </Banner>
                    )}
                    {isPaidPlan && (
                      <Text as="p" variant="bodyMd">
                        {I18n.t("add_partial_payment_options.show_this_payment_rule_only_for")}
                      </Text>
                    )}
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <Checkbox
                      label={I18n.t("add_partial_payment_options.enable_zipcode_includes")}
                      helpText={
                        isPaidPlan
                          ? "When enabled, this rule will be shown only for customers with the specified zipcodes"
                          : undefined
                      }
                      checked={zipcodeWhitelistEnabled}
                      onChange={(checked) => {
                        setZipcodeWhitelistEnabled(checked);
                        setIsDirty(true);
                      }}
                      disabled={!isPaidPlan}
                    />
                    {zipcodeWhitelistEnabled && isPaidPlan && (
                      <BlockStack gap="300">
                        <TextField
                          label={I18n.t("add_partial_payment_options.zipcodes_to_include_for_this_rule")}
                          value={zipcodeWhitelist ?? ""}
                          onChange={(value) => {
                            setZipcodeWhitelist(value);
                            setIsDirty(true);
                          }}
                          autoComplete="off"
                          multiline={3}
                          placeholder="110001, 110002, 400001-400010"
                          helpText={I18n.t("add_partial_payment_options.enter_zipcodes_separated_by_commas_supports")}
                          disabled={!isPaidPlan}
                        />
                        <Box
                          background="bg-surface-secondary"
                          padding="300"
                          borderRadius="200"
                        >
                          <BlockStack gap="200">
                            <Text as="p" variant="bodySm" fontWeight="semibold">
                              {I18n.t("partial.zipcode_examples_title", { defaultValue: "Examples:" })}
                            </Text>
                            <BlockStack gap="100">
                              <Text as="p" variant="bodySm">
                                <code>110001, 110002, 110003</code> - {I18n.t("partial.zipcode_example_individual", { defaultValue: "Individual zipcodes" })}
                              </Text>
                              <Text as="p" variant="bodySm">
                                <code>400001-400099</code> - {I18n.t("partial.zipcode_example_range", { defaultValue: "Zipcode range (all from 400001 to 400099)" })}
                              </Text>
                              <Text as="p" variant="bodySm">
                                <code>110001, 400001-400010, 560001</code> - {I18n.t("partial.zipcode_example_mixed", { defaultValue: "Mixed: individual + ranges" })}
                              </Text>
                            </BlockStack>
                          </BlockStack>
                        </Box>
                      </BlockStack>
                    )}
                  </BlockStack>
                </Card>
              </InlineGrid>

              <Divider />

              {/* Display Settings (Advanced) */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("partial.display_settings")}
                    </Text>
                    {!isPaidPlan && (
                      <Banner tone="warning" onDismiss={() => {}}>
                        <BlockStack gap="200">
                          <Text as="p" variant="bodyMd">
                            {I18n.t("partial.advanced_paid_plan_only")}{" "}
                            <Link onClick={handleSubscriptionClick} url="#">
                              {I18n.t("partial.upgrade_to_access")}
                            </Link>
                          </Text>
                        </BlockStack>
                      </Banner>
                    )}
                    {isPaidPlan && (
                      <Text as="p" variant="bodyMd">
                        {I18n.t("partial.display_settings_desc")}
                      </Text>
                    )}
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    <TextField
                      label={I18n.t("partial.amount_to_show")}
                      value={amountToShow ?? ""}
                      onChange={(value) => {
                        setAmountToShow(value);
                        setIsDirty(true);
                        setErrorTrigger(false);
                      }}
                      autoComplete="off"
                      helpText={I18n.t("partial.amount_to_show_help")}
                      disabled={!isPaidPlan}
                    />
                    <TextField
                      label={I18n.t("partial.sub_heading")}
                      value={subHeading ?? ""}
                      onChange={(value) => {
                        setSubHeading(value);
                        setIsDirty(true);
                        setErrorTrigger(false);
                      }}
                      autoComplete="off"
                      helpText={I18n.t("partial.sub_heading_help")}
                      disabled={!isPaidPlan}
                    />
                    <TextField
                      label={I18n.t("partial.custom_save_text", { defaultValue: "Savings text" })}
                      value={customSaveText ?? ""}
                      onChange={(value) => {
                        setCustomSaveText(value);
                        setIsDirty(true);
                        setErrorTrigger(false);
                      }}
                      autoComplete="off"
                      placeholder={
                        I18n.t("partial.custom_save_text_placeholder", { defaultValue: "e.g. Save 10% on this order" })
                      }
                      helpText={
                        I18n.t("partial.custom_save_text_help", { defaultValue: "Shown next to the savings icon on this payment option. Leave blank to use the automatic savings line, which only appears when the rule has a discount." })
                      }
                      disabled={!isPaidPlan}
                    />
                    <Divider />
                    <BlockStack gap="300">
                      <Text as="h4" variant="headingSm">
                        {I18n.t("partial.description_template_title", { defaultValue: "Description Template" })}
                      </Text>
                      <TextField
                        label={I18n.t("partial.description_template", { defaultValue: "Description Template" })}
                        value={descriptionTemplate ?? ""}
                        onChange={(value) => {
                          setDescriptionTemplate(value);
                          setIsDirty(true);
                          setErrorTrigger(false);
                        }}
                        autoComplete="off"
                        multiline={2}
                        helpText={
                          I18n.t("partial.description_template_help", { defaultValue: "Customize the payment description shown to customers. Use placeholders: {{pay_now}}, {{pay_later}}, {{total}}, {{discount}}, {{cod_fee}}" })
                        }
                        disabled={!isPaidPlan}
                      />
                      <Box
                        background="bg-surface-secondary"
                        padding="300"
                        borderRadius="200"
                      >
                        <BlockStack gap="300">
                          <Text as="p" variant="bodySm" fontWeight="semibold">
                            {I18n.t("partial.available_placeholders", { defaultValue: "Available Placeholders:" })}
                          </Text>
                          
                          <BlockStack gap="100">
                            <Text as="p" variant="bodySm" fontWeight="medium">
                              {I18n.t("partial.placeholders_pay_now_section", { defaultValue: "Pay Now:" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{pay_now}}"}</code> - {I18n.t("partial.placeholder_pay_now", { defaultValue: "Amount to pay now (with tax)" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{pay_now_base}}"}</code> - {I18n.t("partial.placeholder_pay_now_base", { defaultValue: "Amount to pay now (without tax)" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{pay_now_tax}}"}</code> - {I18n.t("partial.placeholder_pay_now_tax", { defaultValue: "Tax on pay now amount" })}
                            </Text>
                          </BlockStack>

                          <BlockStack gap="100">
                            <Text as="p" variant="bodySm" fontWeight="medium">
                              {I18n.t("partial.placeholders_pay_later_section", { defaultValue: "Pay Later (On Delivery):" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{pay_later}}"}</code> - {I18n.t("partial.placeholder_pay_later", { defaultValue: "Amount on delivery (with tax)" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{pay_later_base}}"}</code> - {I18n.t("partial.placeholder_pay_later_base", { defaultValue: "Amount on delivery (without tax)" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{pay_later_tax}}"}</code> - {I18n.t("partial.placeholder_pay_later_tax", { defaultValue: "Tax on delivery amount" })}
                            </Text>
                          </BlockStack>

                          <BlockStack gap="100">
                            <Text as="p" variant="bodySm" fontWeight="medium">
                              {I18n.t("partial.placeholders_totals_section", { defaultValue: "Totals:" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{total}}"}</code> - {I18n.t("partial.placeholder_total", { defaultValue: "Total amount (with tax)" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{total_base}}"}</code> - {I18n.t("partial.placeholder_total_base", { defaultValue: "Total amount (without tax)" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{total_tax}}"}</code> - {I18n.t("partial.placeholder_total_tax", { defaultValue: "Total tax amount" })}
                            </Text>
                          </BlockStack>

                          <BlockStack gap="100">
                            <Text as="p" variant="bodySm" fontWeight="medium">
                              {I18n.t("partial.placeholders_other_section", { defaultValue: "Other:" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{discount}}"}</code> - {I18n.t("partial.placeholder_discount", { defaultValue: "Discount amount" })}
                            </Text>
                            <Text as="p" variant="bodySm">
                              <code>{"{{cod_fee}}"}</code> - {I18n.t("partial.placeholder_cod_fee", { defaultValue: "COD fee amount" })}
                            </Text>
                          </BlockStack>
                        </BlockStack>
                      </Box>
                      
                      <Box
                        background="bg-surface-caution"
                        padding="300"
                        borderRadius="200"
                      >
                        <BlockStack gap="200">
                          <Text as="p" variant="bodySm" fontWeight="semibold">
                            {I18n.t("partial.example_templates_title", { defaultValue: "Example Templates:" })}
                          </Text>
                          <BlockStack gap="150">
                            <BlockStack gap="050">
                              <Text as="p" variant="bodySm" fontWeight="medium">
                                {I18n.t("partial.example_simple", { defaultValue: "Simple (tax included):" })}
                              </Text>
                              <Text as="p" variant="bodySm" tone="subdued">
                                <code>{"Pay {{pay_now}} now and {{pay_later}} on delivery"}</code>
                              </Text>
                            </BlockStack>
                            <BlockStack gap="050">
                              <Text as="p" variant="bodySm" fontWeight="medium">
                                {I18n.t("partial.example_separate_tax", { defaultValue: "Show tax separately:" })}
                              </Text>
                              <Text as="p" variant="bodySm" tone="subdued">
                                <code>{"Pay {{pay_now_base}} + {{pay_now_tax}} tax now, {{pay_later_base}} + {{pay_later_tax}} tax on delivery"}</code>
                              </Text>
                            </BlockStack>
                            <BlockStack gap="050">
                              <Text as="p" variant="bodySm" fontWeight="medium">
                                {I18n.t("partial.example_tax_summary", { defaultValue: "Tax summary at end:" })}
                              </Text>
                              <Text as="p" variant="bodySm" tone="subdued">
                                <code>{"Pay {{pay_now}} now and {{pay_later}} on delivery (includes {{total_tax}} tax)"}</code>
                              </Text>
                            </BlockStack>
                            <BlockStack gap="050">
                              <Text as="p" variant="bodySm" fontWeight="medium">
                                {I18n.t("partial.example_cod_with_fee", { defaultValue: "COD with fee:" })}
                              </Text>
                              <Text as="p" variant="bodySm" tone="subdued">
                                <code>{"Pay {{total}} on delivery ({{cod_fee}} COD charges)"}</code>
                              </Text>
                            </BlockStack>
                          </BlockStack>
                        </BlockStack>
                      </Box>

                      <Button
                        plain
                        onClick={() => {
                          setDescriptionTemplate(getDefaultTemplate());
                          setIsDirty(true);
                        }}
                        disabled={!isPaidPlan}
                      >
                        {I18n.t("partial.reset_to_default_template", { defaultValue: "Reset to default template" })}
                      </Button>
                    </BlockStack>
                  </BlockStack>
                </Card>
              </InlineGrid>
            </BlockStack>
          </Box>
        </Layout.Section>

      </Layout>
    </Page>
  );
}
