import React, { useCallback, useContext, useEffect, useMemo, useState } from "react";
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
  List,
} from "@shopify/polaris";
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import { StoreContext } from "../../Context/Store";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import { hasNoChargeId } from "../../utils/shopUtils";
import { navigateTo } from "../../../utils/navigate";
import FeatureCallout from "../FeatureCallout";

const PREPAID_DISCOUNT_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-17_at_2.13.16_PM.jpg?v=1791392606";

function isFullPaymentRule(rule) {
  const amountType = rule?.amount_type || rule?.amountType;
  const amount = Number(rule?.amount ?? 0);
  return amountType === "percentage" && amount === 100;
}

export default function PrepaidDiscount() {
  const shopify = useAppBridge();
  const {
    shop: [shop],
    plan: [plan],
    setting: [setting, setSetting],
    originalSetting: [, setOriginalSetting],
  } = useContext(StoreContext);

  const isPaidPlan =
    plan?.name?.toLowerCase() !== "free" && !hasNoChargeId(shop);

  const [rules, setRules] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const fullPaymentRule = useMemo(
    () => (rules || []).find((r) => isFullPaymentRule(r)),
    [rules],
  );

  const discountEnabled = useMemo(() => {
    if (!fullPaymentRule) return false;
    const dv = fullPaymentRule.discount_value ?? fullPaymentRule.discountValue;
    return String(dv || "").trim().length > 0;
  }, [fullPaymentRule]);

  const [enableDiscount, setEnableDiscount] = useState(false);
  const [discountType, setDiscountType] = useState("fixed");
  const [discountValue, setDiscountValue] = useState("");
  const [discountCode, setDiscountCode] = useState("");
  const [combinesWithOrder, setCombinesWithOrder] = useState(false);
  const [combinesWithProduct, setCombinesWithProduct] = useState(false);
  const [combinesWithShipping, setCombinesWithShipping] = useState(false);

  const fetchRules = useCallback(() => {
    setLoading(true);
    return Api.get("/partial_rule_sets")
      .then((res) => {
        setRules(Array.isArray(res.data) ? res.data : []);
      })
      .catch(() => setRules([]))
      .finally(() => setLoading(false));
  }, []);

  const ensureFullPaymentRule = useCallback(async () => {
    // Create a full-payment rule if missing (percentage=100).
    const existing = (rules || []).find((r) => isFullPaymentRule(r));
    if (existing) return;

    const payload = {
      rule_name: I18n.t("partial.full_payment_label"),
      amount: 100,
      amount_type: "percentage",
      product_scope: "all",
      product_ids: "",
      is_all: true,
      is_enabled: true,
      is_cart_rule: true,
      discount_code: "",
      discount_value: "",
      discount_type: "fixed",
      variant_scope: "all",
      variant_ids: [],
    };

    try {
      await Api.post("/partial_rule_sets", { partial_rule_set: payload });
      await fetchRules();
    } catch (e) {
      // Non-fatal; user can retry save/fetch.
      console.error("Failed to create full payment rule:", e);
    }
  }, [rules, fetchRules]);

  // Initial load
  useEffect(() => {
    fetchRules();
  }, [fetchRules]);

  // Keep local form state in sync once rule exists/changes
  useEffect(() => {
    const r = fullPaymentRule;
    if (!r) return;

    const dv = String(r.discount_value ?? r.discountValue ?? "").trim();
    const dt = String(r.discount_type ?? r.discountType ?? "fixed").trim();
    const dc = String(r.discount_code ?? r.discountCode ?? "").trim();

    setEnableDiscount(dv.length > 0);
    setDiscountType(dt || "fixed");
    setDiscountValue(dv);
    setDiscountCode(dc);
  }, [fullPaymentRule?.id]); // only when switching/creating the rule

  // Auto-create rule after initial fetch if missing
  useEffect(() => {
    if (!loading) ensureFullPaymentRule();
  }, [loading, ensureFullPaymentRule]);

  useEffect(() => {
    if (!setting) return;
    setCombinesWithOrder(setting.partialDiscountCombinesWithOrder === true);
    setCombinesWithProduct(setting.partialDiscountCombinesWithProduct === true);
    setCombinesWithShipping(
      setting.partialDiscountCombinesWithShipping === true,
    );
  }, [
    setting?.partialDiscountCombinesWithOrder,
    setting?.partialDiscountCombinesWithProduct,
    setting?.partialDiscountCombinesWithShipping,
  ]);

  // What the form would show if it were reloaded now. Comparing against this
  // rather than tracking a dirty flag means a save clears the bar on its own:
  // fetchRules and setSetting refresh both sources.
  const savedValues = useMemo(() => {
    const r = fullPaymentRule;
    const dv = String(r?.discount_value ?? r?.discountValue ?? "").trim();
    return {
      enableDiscount: dv.length > 0,
      discountType:
        String(r?.discount_type ?? r?.discountType ?? "fixed").trim() || "fixed",
      discountValue: dv,
      discountCode: String(r?.discount_code ?? r?.discountCode ?? "").trim(),
      combinesWithOrder: setting?.partialDiscountCombinesWithOrder === true,
      combinesWithProduct: setting?.partialDiscountCombinesWithProduct === true,
      combinesWithShipping:
        setting?.partialDiscountCombinesWithShipping === true,
    };
  }, [
    fullPaymentRule,
    setting?.partialDiscountCombinesWithOrder,
    setting?.partialDiscountCombinesWithProduct,
    setting?.partialDiscountCombinesWithShipping,
  ]);

  const isDirty = useMemo(
    () =>
      enableDiscount !== savedValues.enableDiscount ||
      discountType !== savedValues.discountType ||
      discountValue !== savedValues.discountValue ||
      discountCode !== savedValues.discountCode ||
      combinesWithOrder !== savedValues.combinesWithOrder ||
      combinesWithProduct !== savedValues.combinesWithProduct ||
      combinesWithShipping !== savedValues.combinesWithShipping,
    [
      savedValues,
      enableDiscount,
      discountType,
      discountValue,
      discountCode,
      combinesWithOrder,
      combinesWithProduct,
      combinesWithShipping,
    ],
  );

  const handleDiscard = useCallback(() => {
    setEnableDiscount(savedValues.enableDiscount);
    setDiscountType(savedValues.discountType);
    setDiscountValue(savedValues.discountValue);
    setDiscountCode(savedValues.discountCode);
    setCombinesWithOrder(savedValues.combinesWithOrder);
    setCombinesWithProduct(savedValues.combinesWithProduct);
    setCombinesWithShipping(savedValues.combinesWithShipping);
  }, [savedValues]);

  const handleSave = useCallback(async () => {
    if (!fullPaymentRule) {
      shopify?.toast?.show(I18n.t("prepaid_discount.error_missing_rule"), {
        isError: true,
      });
      return;
    }

    if (!isPaidPlan) {
      shopify?.toast?.show(I18n.t("prepaid_discount.paid_plan_required"), {
        isError: true,
      });
      return;
    }

    setSaving(true);
    try {
      const updatedRule = {
        ...fullPaymentRule,
        discount_type: enableDiscount ? discountType : "",
        discount_value: enableDiscount ? discountValue : "",
        discount_code: enableDiscount ? discountCode : "",
        // Use the discount template when discount is enabled; otherwise default template.
        description_template: enableDiscount
          ? "Pay {{pay_now}} now and get {{discount}} off"
          : "",
      };

      await Api.put(`/partial_rule_sets/${fullPaymentRule.id}`, {
        partial_rule_set: updatedRule,
      });

      // Ensure partial payment is enabled in settings on save.
      const nextSetting = {
        ...setting,
        partialPaymentEnabled: true,
        partialDiscountCombinesWithOrder: combinesWithOrder,
        partialDiscountCombinesWithProduct: combinesWithProduct,
        partialDiscountCombinesWithShipping: combinesWithShipping,
      };
      const settingsResp = await Api.post("/settings", { setting: nextSetting });
      setSetting(settingsResp.data);
      setOriginalSetting(settingsResp.data);

      await fetchRules();
      shopify?.toast?.show(I18n.t("admin.settings_saved"));
    } catch (e) {
      console.error("Prepaid discount save failed:", e);
      shopify?.toast?.show(I18n.t("admin.settings_error"), { isError: true });
    } finally {
      setSaving(false);
    }
  }, [
    fullPaymentRule,
    isPaidPlan,
    enableDiscount,
    discountType,
    discountValue,
    discountCode,
    combinesWithOrder,
    combinesWithProduct,
    combinesWithShipping,
    setting,
    setSetting,
    setOriginalSetting,
    fetchRules,
    shopify,
  ]);

  const discountTypeOptions = useMemo(
    () => [
      { label: I18n.t("prepaid_discount.discount_type_fixed"), value: "fixed" },
      {
        label: I18n.t("prepaid_discount.discount_type_percentage"),
        value: "percentage",
      },
    ],
    [],
  );

  return (
    <Page
      title={I18n.t("prepaid_discount.title")}
      subtitle={I18n.t("prepaid_discount.subtitle")}
      fullWidth={true}
    >
      <SaveBar
        id="prepaid-discount-save-bar"
        open={isDirty && isPaidPlan && !loading}
      >
        <button
          variant="primary"
          onClick={handleSave}
          loading={saving ? "" : undefined}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>{I18n.t("admin.discard")}</button>
      </SaveBar>

      <Layout>
        <Layout.Section>
          <Box paddingBlockEnd="400">
            <FeatureCallout
              illustration="prepaid"
              image={PREPAID_DISCOUNT_CALLOUT_IMAGE}
              title={I18n.t("prepaid_discount.title")}
              description={I18n.t("prepaid_discount.subtitle")}
              docsUrl="https://codking.tech/documentation/"
              showChat
            />
          </Box>

          {!isPaidPlan && (
            <Box paddingBlockEnd="400">
              <Banner tone="warning">
                <Text as="p" variant="bodyMd">
                  {I18n.t("prepaid_discount.paid_plan_notice")}{" "}
                  <Button
                    variant="plain"
                    onClick={() => navigateTo("/subscription")}
                  >
                    {I18n.t("prepaid_discount.upgrade_cta")}
                  </Button>
                </Text>
              </Banner>
            </Box>
          )}

          {/* How the discount reaches the shopper, read before the
              settings that shape it rather than off in a side rail. */}
          <Box paddingBlockEnd="400">
            <Card>
              <Box padding="600">
                <BlockStack gap="400">
                  <BlockStack gap="300">
                    <Text variant="headingMd" as="h2">
                      {I18n.t("prepaid_discount.what_is_this")}
                    </Text>
                    <List type="number">
                      <List.Item>
                        {I18n.t("prepaid_discount.how_it_works_step_1")}
                      </List.Item>
                      <List.Item>
                        {I18n.t("prepaid_discount.how_it_works_step_2")}
                      </List.Item>
                      <List.Item>
                        {I18n.t("prepaid_discount.how_it_works_step_3")}
                      </List.Item>
                    </List>
                  </BlockStack>

                  <Divider />

                  <BlockStack gap="300">
                    <Text variant="headingSm" as="h3">
                      {I18n.t("prepaid_discount.payment_rules_heading")}
                    </Text>
                    <Text variant="bodySm" tone="subdued" as="p">
                      {I18n.t("prepaid_discount.payment_rules_body")}
                    </Text>
                    <Button
                      variant="secondary"
                      onClick={() => navigateTo("/features/partial-payment")}
                    >
                      {I18n.t("prepaid_discount.payment_rules_cta")}
                    </Button>
                  </BlockStack>

                </BlockStack>
              </Box>
            </Card>
          </Box>

          <Card>
            <Box padding="600">
              <BlockStack gap="400">
                <Text variant="headingMd" as="h2">
                  {I18n.t("prepaid_discount.settings_heading")}
                </Text>

                <Text variant="bodySm" tone="subdued" as="p">
                  {I18n.t("prepaid_discount.settings_help")}
                </Text>

                <Divider />

                <InlineStack align="space-between" blockAlign="center">
                  <Text variant="bodyMd" as="p">
                    {I18n.t("prepaid_discount.enable_discount")}
                  </Text>
                  <Checkbox
                    checked={enableDiscount}
                    onChange={setEnableDiscount}
                    disabled={!isPaidPlan || loading}
                  />
                </InlineStack>

                <InlineStack gap="400" wrap={false}>
                  <Select
                    label={I18n.t("prepaid_discount.discount_type")}
                    options={discountTypeOptions}
                    value={discountType}
                    onChange={setDiscountType}
                    disabled={!enableDiscount || !isPaidPlan || loading}
                  />
                  <TextField
                    label={I18n.t("prepaid_discount.discount_value")}
                    value={discountValue}
                    onChange={setDiscountValue}
                    disabled={!enableDiscount || !isPaidPlan || loading}
                    autoComplete="off"
                  />
                </InlineStack>

                <TextField
                  label={I18n.t("prepaid_discount.discount_code")}
                  value={discountCode}
                  onChange={setDiscountCode}
                  disabled={!enableDiscount || !isPaidPlan || loading}
                  autoComplete="off"
                />
              </BlockStack>
            </Box>
          </Card>

          <Box paddingBlockStart="400">
            <Card>
              <Box padding="600">
                <BlockStack gap="400">
                  <BlockStack gap="200">
                    <Text variant="headingMd" as="h2">
                      {I18n.t("prepaid_discount.combinations_heading")}
                    </Text>
                    <Text variant="bodySm" tone="subdued" as="p">
                      {I18n.t("prepaid_discount.combinations_help")}
                    </Text>
                  </BlockStack>

                  <Divider />

                  <BlockStack gap="300">
                    <Checkbox
                      label={I18n.t("prepaid_discount.combines_with_product")}
                      helpText={I18n.t(
                        "prepaid_discount.combines_with_product_help",
                      )}
                      checked={combinesWithProduct}
                      onChange={setCombinesWithProduct}
                      disabled={!isPaidPlan || loading}
                    />
                    <Checkbox
                      label={I18n.t("prepaid_discount.combines_with_order")}
                      helpText={I18n.t(
                        "prepaid_discount.combines_with_order_help",
                      )}
                      checked={combinesWithOrder}
                      onChange={setCombinesWithOrder}
                      disabled={!isPaidPlan || loading}
                    />
                    <Checkbox
                      label={I18n.t("prepaid_discount.combines_with_shipping")}
                      helpText={I18n.t(
                        "prepaid_discount.combines_with_shipping_help",
                      )}
                      checked={combinesWithShipping}
                      onChange={setCombinesWithShipping}
                      disabled={!isPaidPlan || loading}
                    />
                  </BlockStack>
                </BlockStack>
              </Box>
            </Card>
          </Box>
        </Layout.Section>
      </Layout>
    </Page>
  );
}

