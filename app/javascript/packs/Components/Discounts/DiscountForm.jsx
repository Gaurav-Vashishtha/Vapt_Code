import React, { useCallback, useContext, useMemo, useState } from "react";
import {
  Page,
  Layout,
  Card,
  Box,
  Text,
  InlineStack,
  BlockStack,
  Button,
  Banner,
  Checkbox,
  TextField,
  Select,
  Divider,
  Tag,
  List,
} from "@shopify/polaris";
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import { StoreContext } from "../../Context/Store";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";

const METHOD_OPTIONS = [
  { get label() {
      return I18n.t("discount_form.discount_code_customer_enters_a_code");
    }, value: "code" },
  { get label() {
      return I18n.t("discount_form.automatic_applied_automatically");
    }, value: "automatic" },
];

const TYPE_OPTIONS = [
  { get label() {
      return I18n.t("discount_form.percentage_off");
    }, value: "percentage" },
  { get label() {
      return I18n.t("discount_form.fixed_amount_off");
    }, value: "amount_off" },
];

const APPLIES_TO_OPTIONS = [
  { get label() {
      return I18n.t("discount_form.all_products");
    }, value: "all" },
  { get label() {
      return I18n.t("discount_form.specific_products");
    }, value: "products" },
  { get label() {
      return I18n.t("discount_form.specific_collections");
    }, value: "collections" },
];

const MIN_REQ_OPTIONS = [
  { get label() {
      return I18n.t("discount_form.no_minimum_requirement");
    }, value: "" },
  { get label() {
      return I18n.t("discount_form.minimum_purchase_amount");
    }, value: "subtotal" },
  { get label() {
      return I18n.t("discount_form.minimum_quantity_of_items");
    }, value: "quantity" },
];

const BUYS_TYPE_OPTIONS = [
  { get label() {
      return I18n.t("discount_form.minimum_quantity_of_items");
    }, value: "quantity" },
  { get label() {
      return I18n.t("discount_form.minimum_purchase_amount");
    }, value: "amount" },
];

function randomCode() {
  const r = Math.random().toString(36).slice(2, 10).toUpperCase();
  return `CODK-${r}`;
}

function gidLabel(gid) {
  return gid.split("/").pop();
}

// Maps a server (camelized) discount record into editable form state.
function toFormState(d) {
  const bx = d?.bxgyConfig || {};
  return {
    title: d?.title || "",
    method: d?.method || "code",
    code: d?.code || "",
    discountType: d?.discountType || "percentage",
    value: d?.value != null ? String(d.value) : "",
    appliesTo: d?.appliesTo || "all",
    productGids: d?.productGids || [],
    collectionGids: d?.collectionGids || [],
    excludedProductGids: d?.excludedProductGids || [],
    minimumRequirementType: d?.minimumRequirementType || "",
    minimumRequirementValue:
      d?.minimumRequirementValue != null ? String(d.minimumRequirementValue) : "",
    usageLimit: d?.usageLimit != null ? String(d.usageLimit) : "",
    oncePerCustomer: !!d?.oncePerCustomer,
    combinesWithOrder: d?.combinesWithOrder ?? true,
    combinesWithProduct: d?.combinesWithProduct ?? false,
    combinesWithShipping: d?.combinesWithShipping ?? true,
    widgetEnabled: d?.widgetEnabled ?? true,
    headline: d?.headline || "",
    unlockText: d?.unlockText || "",
    displayOrder: d?.displayOrder != null ? String(d.displayOrder) : "0",
    bxgy: {
      buysType: bx.buysType || "quantity",
      buysValue: bx.buysValue != null ? String(bx.buysValue) : "",
      buysItems: bx.buysItems || "all",
      buysProductGids: bx.buysProductGids || [],
      buysCollectionGids: bx.buysCollectionGids || [],
      getsQty: bx.getsQty != null ? String(bx.getsQty) : "1",
      getsEffectValue: bx.getsEffectValue != null ? String(bx.getsEffectValue) : "100",
    },
  };
}

export default function DiscountForm({ discount, onBack, onSaved }) {
  const shopify = useAppBridge();
  const {
    setting: [setting],
  } = useContext(StoreContext);

  const isEdit = !!discount?.id;
  const [form, setForm] = useState(() => toFormState(discount));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  const set = useCallback((key, val) => setForm((f) => ({ ...f, [key]: val })), []);
  const setBx = useCallback(
    (key, val) => setForm((f) => ({ ...f, bxgy: { ...f.bxgy, [key]: val } })),
    [],
  );

  // The form as it would load from the saved record. Comparing against this
  // needs no dirty flag, and a new discount reads as dirty the moment the
  // merchant types anything.
  const savedForm = useMemo(() => toFormState(discount), [discount]);
  const isDirty = useMemo(
    () => JSON.stringify(form) !== JSON.stringify(savedForm),
    [form, savedForm],
  );
  const handleDiscard = useCallback(() => {
    setForm(savedForm);
    setError(null);
  }, [savedForm]);

  const isCode = form.method === "code";
  const isBxgy = form.discountType === "buy_x_get_y";

  // "Exceptions" — product titles keyed by gid, so the selected tags read nicely.
  const [exclLabels, setExclLabels] = useState({});

  // Generic resource picker that returns full GIDs (we store gid://shopify/...).
  const openPicker = useCallback(
    async (type, currentGids, onChange) => {
      try {
        const selected = await shopify.resourcePicker({
          type,
          multiple: true,
          selectionIds: (currentGids || []).map((id) => ({ id })),
          action: "select",
        });
        if (selected) {
          onChange([...new Set(selected.map((item) => item.id))]);
        }
      } catch (err) {
        console.error(`${type} picker error`, err);
      }
    },
    [shopify],
  );

  // Exceptions picker: native product picker, then server-side membership filter.
  const openExceptionsPicker = useCallback(async () => {
    if (form.collectionGids.length === 0) return;
    try {
      const selected = await shopify.resourcePicker({
        type: "product",
        multiple: true,
        action: "select",
        selectionIds: form.excludedProductGids.map((id) => ({ id })),
        filter: { variants: false },
      });
      if (!selected) return;

      const picked = [...new Set(selected.map((p) => p.id))];
      const res = await Api.post("/discounts/validate_exceptions", {
        product_gids: picked,
        collection_gids: form.collectionGids,
      });
      const members = res?.data?.products || [];

      setExclLabels((m) => {
        const next = { ...m };
        members.forEach((p) => (next[p.id] = p.title));
        return next;
      });
      set("excludedProductGids", members.map((p) => p.id));

      const dropped = picked.length - members.length;
      if (dropped > 0) {
        shopify?.toast?.show(
          `${dropped} product${dropped > 1 ? "s aren’t" : " isn’t"} in the selected collection${form.collectionGids.length > 1 ? "s" : ""} and ${dropped > 1 ? "were" : "was"} skipped.`,
          { isError: true },
        );
      }
    } catch (err) {
      console.error("exceptions picker error", err);
    }
  }, [shopify, form.collectionGids, form.excludedProductGids, set]);

  const validate = useCallback(() => {
    if (!form.title.trim()) return "Title is required.";
    if (isCode && !form.code.trim()) return "Discount code is required for code discounts.";
    if (!isBxgy && !String(form.value).trim()) return "Discount value is required.";
    if (form.appliesTo === "products" && form.productGids.length === 0)
      return "Select at least one product.";
    if (form.appliesTo === "collections" && form.collectionGids.length === 0)
      return "Select at least one collection.";
    if (isBxgy && !String(form.bxgy.buysValue).trim())
      return "Enter the buy quantity/amount for the Buy X Get Y discount.";
    if (form.minimumRequirementType && !String(form.minimumRequirementValue).trim())
      return "Enter the minimum requirement value.";
    return null;
  }, [form, isCode, isBxgy]);

  const buildPayload = useCallback(() => {
    const payload = {
      title: form.title.trim(),
      method: form.method,
      code: isCode ? form.code.trim() : null,
      discountType: form.discountType,
      value: isBxgy ? null : Number(form.value),
      appliesTo: form.appliesTo,
      productGids: form.appliesTo === "products" ? form.productGids : [],
      collectionGids: form.appliesTo === "collections" ? form.collectionGids : [],
      excludedProductGids:
        form.appliesTo === "collections" ? form.excludedProductGids : [],
      minimumRequirementType: form.minimumRequirementType || null,
      minimumRequirementValue: form.minimumRequirementType
        ? Number(form.minimumRequirementValue)
        : null,
      usageLimit: form.usageLimit ? Number(form.usageLimit) : null,
      oncePerCustomer: form.oncePerCustomer,
      combinesWithOrder: form.combinesWithOrder,
      combinesWithProduct: form.combinesWithProduct,
      combinesWithShipping: form.combinesWithShipping,
      widgetEnabled: form.widgetEnabled,
      headline: form.headline,
      unlockText: form.unlockText,
      displayOrder: Number(form.displayOrder) || 0,
    };
    if (isBxgy) {
      payload.bxgyConfig = {
        buysType: form.bxgy.buysType,
        buysValue: form.bxgy.buysValue,
        buysItems: form.bxgy.buysItems,
        buysProductGids:
          form.bxgy.buysItems === "products" ? form.bxgy.buysProductGids : [],
        buysCollectionGids:
          form.bxgy.buysItems === "collections" ? form.bxgy.buysCollectionGids : [],
        getsQty: form.bxgy.getsQty,
        getsEffectValue: form.bxgy.getsEffectValue,
      };
    }
    return payload;
  }, [form, isCode, isBxgy]);

  const handleSave = useCallback(async () => {
    const validationError = validate();
    if (validationError) {
      setError(validationError);
      return;
    }
    setError(null);
    setSaving(true);
    try {
      const body = { discount: buildPayload() };
      if (isEdit) {
        await Api.put(`/discounts/${discount.id}`, body);
      } else {
        await Api.post("/discounts", body);
      }
      shopify?.toast?.show("Discount saved. Syncing to Shopify…");
      onSaved?.();
    } catch (e) {
      const msg = e?.response?.data?.errors?.join(", ") || "Failed to save discount.";
      setError(msg);
      shopify?.toast?.show(msg, { isError: true });
    } finally {
      setSaving(false);
    }
  }, [validate, buildPayload, isEdit, discount, shopify, onSaved]);

  const valueSuffix = form.discountType === "percentage" ? "%" : "";

  // Live "Summary" side panel that mirrors Shopify's native discount detail page.
  const summary = useMemo(() => {
    const typeAndMethod = [];
    typeAndMethod.push(
      form.method === "code"
        ? `Code${form.code ? ` · ${form.code}` : ""}`
        : "Automatic discount",
    );
    if (isBxgy) {
      const buys =
        form.bxgy.buysType === "amount"
          ? `Spend ${form.bxgy.buysValue || 0}`
          : `Buy ${form.bxgy.buysValue || 0} item(s)`;
      typeAndMethod.push(
        `${buys}, get ${form.bxgy.getsQty || 0} at ${form.bxgy.getsEffectValue || 0}% off`,
      );
    } else {
      typeAndMethod.push(
        form.discountType === "percentage"
          ? `${form.value || 0}% off`
          : `${form.value || 0} off`,
      );
    }

    const details = [];
    if (form.appliesTo === "all") details.push("Applies to all products");
    else if (form.appliesTo === "products")
      details.push(`Applies to ${form.productGids.length} product(s)`);
    else if (form.appliesTo === "collections") {
      details.push(`Applies to ${form.collectionGids.length} collection(s)`);
      if (form.excludedProductGids.length)
        details.push(`${form.excludedProductGids.length} exception(s)`);
    }

    if (!form.minimumRequirementType) details.push("No minimum requirement");
    else if (form.minimumRequirementType === "subtotal")
      details.push(`Minimum purchase of ${form.minimumRequirementValue || 0}`);
    else if (form.minimumRequirementType === "quantity")
      details.push(`Minimum of ${form.minimumRequirementValue || 0} items`);

    if (form.method === "code") {
      details.push(
        form.usageLimit
          ? `Limited to ${form.usageLimit} total use(s)`
          : "No usage limit",
      );
      if (form.oncePerCustomer) details.push("One use per customer");
    }

    const combos = [
      form.combinesWithOrder && "order",
      form.combinesWithProduct && "product",
      form.combinesWithShipping && "shipping",
    ].filter(Boolean);
    details.push(
      combos.length
        ? `Combines with ${combos.join(", ")} discounts`
        : "Doesn’t combine with other discounts",
    );

    details.push(
      form.widgetEnabled
        ? "Shown as a coupon on the storefront widget"
        : "Hidden from the storefront widget",
    );

    return { typeAndMethod, details };
  }, [form, isBxgy]);

  const pickerRow = (label, gids, type, onChange) => (
    <BlockStack gap="200">
      <InlineStack align="space-between" blockAlign="center">
        <Text as="span" variant="bodyMd">
          {label}
        </Text>
        <Button onClick={() => openPicker(type, gids, onChange)}>
          {gids.length ? "Edit selection" : `Select ${type}s`}
        </Button>
      </InlineStack>
      {gids.length > 0 && (
        <InlineStack gap="200" wrap>
          {gids.map((g) => (
            <Tag key={g} onRemove={() => onChange(gids.filter((x) => x !== g))}>
              {`${type} ${gidLabel(g)}`}
            </Tag>
          ))}
        </InlineStack>
      )}
    </BlockStack>
  );

  return (
    <Page
      title={isEdit ? "Edit discount" : "Create discount"}
      backAction={{ content: I18n.t("discount_form.discounts"), onAction: onBack }}
      fullWidth={true}
    >
      <SaveBar id="discount-form-save-bar" open={isDirty}>
        <button
          variant="primary"
          onClick={handleSave}
          loading={saving ? "" : undefined}
        >
          {isEdit ? "Save" : "Create discount"}
        </button>
        <button onClick={handleDiscard}>{I18n.t("discount_form.discard")}</button>
      </SaveBar>

      <Layout>
        <Layout.Section>
          {error && (
            <Box paddingBlockEnd="400">
              <Banner tone="critical" onDismiss={() => setError(null)}>
                {error}
              </Banner>
            </Box>
          )}

          {/* Method + type */}
          <Card>
            <Box padding="600">
              <BlockStack gap="400">
                <Text variant="headingMd" as="h2">
                  {I18n.t("discount_form.discount_details")}
                </Text>
                <TextField
                  label={I18n.t("discount_form.title_internal_name")}
                  value={form.title}
                  onChange={(v) => set("title", v)}
                  autoComplete="off"
                />
                <Select
                  label={I18n.t("discount_form.method")}
                  options={METHOD_OPTIONS}
                  value={form.method}
                  onChange={(v) => set("method", v)}
                />
                {isCode && (
                  <InlineStack gap="200" blockAlign="end" wrap={false}>
                    <div style={{ flex: 1 }}>
                      <TextField
                        label={I18n.t("discount_form.discount_code")}
                        value={form.code}
                        onChange={(v) => set("code", v.toUpperCase())}
                        autoComplete="off"
                      />
                    </div>
                    <Button onClick={() => set("code", randomCode())}>{I18n.t("discount_form.generate")}</Button>
                  </InlineStack>
                )}
                <Select
                  label={I18n.t("discount_form.type")}
                  options={TYPE_OPTIONS}
                  value={form.discountType}
                  onChange={(v) => set("discountType", v)}
                />
                {!isBxgy && (
                  <TextField
                    label={I18n.t("discount_form.value")}
                    type="number"
                    value={form.value}
                    onChange={(v) => set("value", v)}
                    suffix={valueSuffix}
                    autoComplete="off"
                    helpText={
                      form.discountType === "percentage"
                        ? "Enter 10 for 10% off."
                        : "Fixed amount off the order."
                    }
                  />
                )}
              </BlockStack>
            </Box>
          </Card>

          {/* BXGY config */}
          {isBxgy && (
            <Box paddingBlockStart="400">
              <Card>
                <Box padding="600">
                  <BlockStack gap="400">
                    <Text variant="headingMd" as="h2">
                      {I18n.t("discount_form.buy_x_get_y")}
                    </Text>
                    <Text variant="bodySm" tone="subdued" as="p">
                      {I18n.t("discount_form.v1_supports_a_percentage_off_the")}
                    </Text>
                    <Divider />
                    <Text variant="headingSm" as="h3">
                      {I18n.t("discount_form.customer_buys")}
                    </Text>
                    <InlineStack gap="400" wrap={false}>
                      <Select
                        label={I18n.t("discount_form.requirement")}
                        options={BUYS_TYPE_OPTIONS}
                        value={form.bxgy.buysType}
                        onChange={(v) => setBx("buysType", v)}
                      />
                      <TextField
                        label={form.bxgy.buysType === "amount" ? "Amount" : "Quantity"}
                        type="number"
                        value={form.bxgy.buysValue}
                        onChange={(v) => setBx("buysValue", v)}
                        autoComplete="off"
                      />
                    </InlineStack>
                    <Select
                      label={I18n.t("discount_form.buy_items_from")}
                      options={APPLIES_TO_OPTIONS}
                      value={form.bxgy.buysItems}
                      onChange={(v) => setBx("buysItems", v)}
                    />
                    {form.bxgy.buysItems === "products" &&
                      pickerRow("Buy products", form.bxgy.buysProductGids, "product", (g) =>
                        setBx("buysProductGids", g),
                      )}
                    {form.bxgy.buysItems === "collections" &&
                      pickerRow(
                        "Buy collections",
                        form.bxgy.buysCollectionGids,
                        "collection",
                        (g) => setBx("buysCollectionGids", g),
                      )}
                    <Divider />
                    <Text variant="headingSm" as="h3">
                      {I18n.t("discount_form.customer_gets")}
                    </Text>
                    <InlineStack gap="400" wrap={false}>
                      <TextField
                        label={I18n.t("discount_form.quantity")}
                        type="number"
                        value={form.bxgy.getsQty}
                        onChange={(v) => setBx("getsQty", v)}
                        autoComplete="off"
                      />
                      <TextField
                        label={I18n.t("discount_form.percent_off_the_get_items")}
                        type="number"
                        suffix="%"
                        value={form.bxgy.getsEffectValue}
                        onChange={(v) => setBx("getsEffectValue", v)}
                        autoComplete="off"
                        helpText={I18n.t("discount_form.100_free")}
                      />
                    </InlineStack>
                  </BlockStack>
                </Box>
              </Card>
            </Box>
          )}

          {/* Targeting (the "get Y" set for BXGY, or the discounted set otherwise) */}
          <Box paddingBlockStart="400">
            <Card>
              <Box padding="600">
                <BlockStack gap="400">
                  <Text variant="headingMd" as="h2">
                    {isBxgy ? "Applies to (get items)" : "Applies to"}
                  </Text>
                  <Select
                    label={I18n.t("discount_form.eligible_items")}
                    options={APPLIES_TO_OPTIONS}
                    value={form.appliesTo}
                    onChange={(v) => set("appliesTo", v)}
                  />
                  {form.appliesTo === "products" &&
                    pickerRow("Products", form.productGids, "product", (g) =>
                      set("productGids", g),
                    )}
                  {form.appliesTo === "collections" &&
                    pickerRow("Collections", form.collectionGids, "collection", (g) =>
                      set("collectionGids", g),
                    )}
                  {form.appliesTo === "collections" && (
                    <>
                      <Divider />
                      <InlineStack align="space-between" blockAlign="center">
                        <Text variant="headingSm" as="h3">
                          {I18n.t("discount_form.exceptions")}
                        </Text>
                        <Button
                          disabled={form.collectionGids.length === 0}
                          onClick={openExceptionsPicker}
                        >
                          {form.excludedProductGids.length
                            ? "Edit exceptions"
                            : "Add products"}
                        </Button>
                      </InlineStack>
                      <Text variant="bodySm" tone="subdued" as="p">
                        {I18n.t("discount_form.choose_products_from_the_selected_collection")}
                      </Text>
                      {form.collectionGids.length === 0 && (
                        <Text variant="bodySm" tone="subdued" as="p">
                          {I18n.t("discount_form.select_at_least_one_collection_first")}
                        </Text>
                      )}
                      {form.excludedProductGids.length > 0 && (
                        <InlineStack gap="200" wrap>
                          {form.excludedProductGids.map((g) => (
                            <Tag
                              key={g}
                              onRemove={() =>
                                set(
                                  "excludedProductGids",
                                  form.excludedProductGids.filter((x) => x !== g),
                                )
                              }
                            >
                              {exclLabels[g] || `product ${gidLabel(g)}`}
                            </Tag>
                          ))}
                        </InlineStack>
                      )}
                    </>
                  )}
                </BlockStack>
              </Box>
            </Card>
          </Box>

          {/* Requirements + limits (basic only) */}
          {!isBxgy && (
            <Box paddingBlockStart="400">
              <Card>
                <Box padding="600">
                  <BlockStack gap="400">
                    <Text variant="headingMd" as="h2">
                      {I18n.t("discount_form.minimum_requirement")}
                    </Text>
                    <Select
                      label={I18n.t("discount_form.requirement")}
                      options={MIN_REQ_OPTIONS}
                      value={form.minimumRequirementType}
                      onChange={(v) => set("minimumRequirementType", v)}
                    />
                    {form.minimumRequirementType && (
                      <TextField
                        label={
                          form.minimumRequirementType === "subtotal"
                            ? "Minimum amount"
                            : "Minimum quantity"
                        }
                        type="number"
                        value={form.minimumRequirementValue}
                        onChange={(v) => set("minimumRequirementValue", v)}
                        autoComplete="off"
                      />
                    )}
                  </BlockStack>
                </Box>
              </Card>
            </Box>
          )}
          {/* Maximum discount uses (code discounts only) */}
          {isCode && (
            <Box paddingBlockStart="400">
              <Card>
                <Box padding="600">
                  <BlockStack gap="300">
                    <Text variant="headingMd" as="h2">
                      {I18n.t("discount_form.maximum_discount_uses")}
                    </Text>
                    <TextField
                      label={I18n.t("discount_form.total_usage_limit")}
                      type="number"
                      value={form.usageLimit}
                      onChange={(v) => set("usageLimit", v)}
                      autoComplete="off"
                      helpText={I18n.t("discount_form.leave_blank_for_unlimited")}
                    />
                    <Checkbox
                      label={I18n.t("discount_form.limit_to_one_use_per_customer")}
                      checked={form.oncePerCustomer}
                      onChange={(v) => set("oncePerCustomer", v)}
                    />
                  </BlockStack>
                </Box>
              </Card>
            </Box>
          )}

          {/* Combinations */}
          <Box paddingBlockStart="400">
            <Card>
              <Box padding="600">
                <BlockStack gap="300">
                  <Text variant="headingMd" as="h2">
                    {I18n.t("discount_form.combinations")}
                  </Text>
                  <Text variant="bodySm" tone="subdued" as="p">
                    {I18n.t("discount_form.keep_order_discounts_on_so_this")}
                  </Text>
                  <Checkbox
                    label={I18n.t("discount_form.order_discounts")}
                    checked={form.combinesWithOrder}
                    onChange={(v) => set("combinesWithOrder", v)}
                  />
                  <Checkbox
                    label={I18n.t("discount_form.product_discounts")}
                    checked={form.combinesWithProduct}
                    onChange={(v) => set("combinesWithProduct", v)}
                  />
                  <Checkbox
                    label={I18n.t("discount_form.shipping_discounts")}
                    checked={form.combinesWithShipping}
                    onChange={(v) => set("combinesWithShipping", v)}
                  />
                </BlockStack>
              </Box>
            </Card>
          </Box>

          {/* Widget display (COD app specific) */}
          <Box paddingBlockStart="400">
            <Card>
              <Box padding="600">
                <BlockStack gap="300">
                  <Text variant="headingMd" as="h2">
                    {I18n.t("discount_form.widget_display")}
                  </Text>
                  <Checkbox
                    label={I18n.t("discount_form.show_as_a_coupon_on_the")}
                    checked={form.widgetEnabled}
                    onChange={(v) => set("widgetEnabled", v)}
                  />
                  <TextField
                    label={I18n.t("discount_form.headline")}
                    value={form.headline}
                    onChange={(v) => set("headline", v)}
                    autoComplete="off"
                    placeholder={I18n.t("discount_form.flat_10_off")}
                  />
                  <TextField
                    label={I18n.t("discount_form.unlock_text")}
                    value={form.unlockText}
                    onChange={(v) => set("unlockText", v)}
                    autoComplete="off"
                    placeholder={I18n.t("discount_form.add_remaining_more_to_unlock")}
                  />
                  <TextField
                    label={I18n.t("discount_form.display_order")}
                    type="number"
                    value={form.displayOrder}
                    onChange={(v) => set("displayOrder", v)}
                    autoComplete="off"
                  />
                </BlockStack>
              </Box>
            </Card>
          </Box>
        </Layout.Section>

        {/* Sidebar: live Summary (mirrors Shopify's native discount detail page) */}
        <Layout.Section secondary>
          <Card>
            <Box padding="600">
              <BlockStack gap="400">
                <Text variant="headingMd" as="h2">
                  {I18n.t("discount_form.summary")}
                </Text>
                <Text variant="bodyMd" fontWeight="semibold" as="p">
                  {form.code || form.title || "No title yet"}
                </Text>
                <BlockStack gap="200">
                  <Text variant="headingSm" as="h3">
                    {I18n.t("discount_form.type_and_method")}
                  </Text>
                  <List>
                    {summary.typeAndMethod.map((t, i) => (
                      <List.Item key={i}>{t}</List.Item>
                    ))}
                  </List>
                </BlockStack>
                <Divider />
                <BlockStack gap="200">
                  <Text variant="headingSm" as="h3">
                    {I18n.t("discount_form.details")}
                  </Text>
                  <List>
                    {summary.details.map((t, i) => (
                      <List.Item key={i}>{t}</List.Item>
                    ))}
                  </List>
                </BlockStack>
              </BlockStack>
            </Box>
          </Card>
        </Layout.Section>
      </Layout>
    </Page>
  );
}
