import React from "react";
import { BlockStack, Checkbox, Divider, InlineGrid, Select, Text, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import Gate from "../components/Gate";
import { FEATURES } from "../constants";
import { toInt, toNumber } from "../utils";
import { t } from "../i18n";

/**
 * Remaining `general` settings: COD only through the form (PRE-3), COD fee
 * tax (FEE-2), discount code field (FRM-16, OFF-8), prepaid options,
 * abandoned forms (ABN-1..3), upsell window (OFF-10), embedded mode (FRM-20),
 * consent (TRK-6), branding. Shown on the Advanced settings page; address
 * autocomplete has its own card on Setup (AutocompleteCard).
 */
const AdvancedCard = ({ general, onChange }) => {
  const abandonment = general.abandonment || {};
  const recovery = abandonment.recovery_discount || {};
  const embedded = general.embedded || {};
  const discounts = general.discounts || {};
  const prepaid = general.prepaid || {};

  return (
    <SectionCard
      title={t("setup.advanced_form_title", "Form behaviour")}
      description={t("setup.advanced_help", "Optional behaviour of the form. The defaults suit most stores.")}
    >
      <BlockStack gap="400">
        <Checkbox
          label={t("setup.cod_only_through_form", "COD only through the form")}
          helpText={t("setup.cod_only_through_form_help", "Hides Cash on delivery at Shopify checkout so COD orders always come through the form. This is saved now and takes effect at checkout with the next COD King checkout update.")}
          checked={!!general.cod_only_through_form}
          onChange={(value) => onChange(["cod_only_through_form"], value)}
        />
        <Checkbox
          label={t("setup.cod_fee_taxable", "Charge tax on the COD fee")}
          helpText={t("setup.cod_fee_taxable_help", "The fee itself is set in COD fees and is shown as its own line in the form.")}
          checked={!!general.cod_fee_taxable}
          onChange={(value) => onChange(["cod_fee_taxable"], value)}
        />

        <Divider />
        <Text as="h4" variant="headingSm">
          {t("setup.discounts_title", "Discount codes")}
        </Text>
        <Gate feature={FEATURES.DISCOUNT_CODE_FIELD} compact title={t("setup.discounts_title", "Discount codes")}>
          <BlockStack gap="200">
            <Checkbox
              label={t("setup.code_field_enabled", "Let buyers enter a Shopify discount code")}
              helpText={t("setup.code_field_help", "The Discount block must also be on in Form designer.")}
              checked={!!discounts.code_field_enabled}
              onChange={(value) => onChange(["discounts", "code_field_enabled"], value)}
            />
            <Checkbox
              label={t("offers.codes_combine", "Discount codes combine with offers")}
              helpText={t("setup.codes_combine_help", "Off: a code replaces quantity-offer and downsell discounts when it is better for the buyer.")}
              checked={!!discounts.codes_combine_with_offers}
              disabled={!discounts.code_field_enabled}
              onChange={(value) => onChange(["discounts", "codes_combine_with_offers"], value)}
            />
          </BlockStack>
        </Gate>

        <Divider />
        <Text as="h4" variant="headingSm">
          {t("setup.prepaid_title", "Pay online")}
        </Text>
        <Checkbox
          label={t("setup.show_pay_online", "Show \"Pay online instead\" in the form")}
          checked={prepaid.show_pay_online !== false}
          onChange={(value) => onChange(["prepaid", "show_pay_online"], value)}
        />

        <Divider />
        <Text as="h4" variant="headingSm">
          {t("setup.abandonment_title", "Abandoned forms")}
        </Text>
        <Gate feature={FEATURES.ABANDONMENT} compact title={t("setup.abandonment_title", "Abandoned forms")}>
          <BlockStack gap="200">
            <Checkbox
              label={t("setup.abandonment_enabled", "Send my abandoned-cart messages for abandoned forms")}
              helpText={t("setup.abandonment_help", "A form with a phone or email and no order after 15 minutes counts as abandoned. This works only when abandoned-cart messages are on in Customer notifications.")}
              checked={abandonment.enabled !== false}
              onChange={(value) => onChange(["abandonment", "enabled"], value)}
            />
            <Checkbox
              label={t("setup.abandonment_draft_order", "Create a Shopify draft order for each abandoned form")}
              checked={!!abandonment.create_draft_order}
              disabled={abandonment.enabled === false}
              onChange={(value) => onChange(["abandonment", "create_draft_order"], value)}
            />
            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
              <Select
                label={t("setup.recovery_discount_type", "Discount in the recovery link")}
                options={[
                  { label: t("setup.recovery_discount_none", "No discount"), value: "" },
                  { label: t("common.percentage", "Percentage"), value: "percentage" },
                  { label: t("common.fixed_amount", "Fixed amount"), value: "fixed_amount" },
                ]}
                value={recovery.type || ""}
                disabled={abandonment.enabled === false}
                onChange={(value) => onChange(["abandonment", "recovery_discount"], { type: value || null, value: value ? recovery.value || 0 : 0 })}
              />
              {recovery.type && (
                <TextField
                  label={
                    recovery.type === "percentage"
                      ? t("setup.recovery_discount_percent", "Percent off")
                      : t("setup.recovery_discount_amount", "Amount off")
                  }
                  type="number"
                  min={0}
                  max={recovery.type === "percentage" ? 100 : undefined}
                  value={
                    recovery.type === "percentage"
                      ? String(recovery.value == null ? "" : recovery.value)
                      : String(recovery.value == null ? "" : Number(recovery.value) / 100)
                  }
                  onChange={(value) => {
                    const number = toNumber(value, 0);
                    onChange(
                      ["abandonment", "recovery_discount", "value"],
                      recovery.type === "percentage" ? Math.min(100, Math.max(0, number)) : Math.round(Math.max(0, number) * 100),
                    );
                  }}
                  suffix={recovery.type === "percentage" ? "%" : undefined}
                  autoComplete="off"
                />
              )}
            </InlineGrid>
          </BlockStack>
        </Gate>

        <Divider />
        <TextField
          label={t("setup.upsell_window", "One-click upsell window (minutes)")}
          helpText={t("setup.upsell_window_help", "How long after the order a buyer can accept the upsell.")}
          type="number"
          min={1}
          max={60}
          value={String(general.upsell_window_minutes == null ? "" : general.upsell_window_minutes)}
          onChange={(value) => onChange(["upsell_window_minutes"], Math.min(60, Math.max(1, toInt(value, 5))))}
          autoComplete="off"
        />

        <Divider />
        <Text as="h4" variant="headingSm">
          {t("setup.embedded_title", "Embedded form on the product page")}
        </Text>
        <Gate feature={FEATURES.EMBEDDED_MODE} compact title={t("setup.embedded_title", "Embedded form on the product page")}>
          <BlockStack gap="200">
            <Checkbox
              label={t("setup.embedded_enabled", "Show the form inline on the product page instead of a popup")}
              checked={!!embedded.enabled}
              onChange={(value) => onChange(["embedded", "enabled"], value)}
            />
            {embedded.enabled && (
              <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                <TextField
                  label={t("setup.embedded_selector", "CSS selector to place the form (optional)")}
                  value={embedded.selector || ""}
                  onChange={(value) => onChange(["embedded", "selector"], value)}
                  placeholder=".product-form"
                  autoComplete="off"
                />
                <Select
                  label={t("setup.embedded_position", "Position")}
                  options={[
                    { label: t("setup.embedded_after", "After the element"), value: "after" },
                    { label: t("setup.embedded_before", "Before the element"), value: "before" },
                    { label: t("setup.embedded_inside", "Inside the element"), value: "inside" },
                  ]}
                  value={embedded.position || "after"}
                  onChange={(value) => onChange(["embedded", "position"], value)}
                />
              </InlineGrid>
            )}
          </BlockStack>
        </Gate>

        <Divider />
        <Checkbox
          label={t("setup.respect_privacy", "Respect the buyer's cookie consent for tracking")}
          helpText={t("setup.respect_privacy_help", "Marketing pixels and funnel analytics follow Shopify's Customer Privacy settings.")}
          checked={general.consent ? general.consent.respect_customer_privacy !== false : true}
          onChange={(value) => onChange(["consent", "respect_customer_privacy"], value)}
        />
        <Gate feature={FEATURES.BRANDING_REMOVAL} compact title={t("setup.hide_powered_by", "Hide \"Powered by COD King\"")}>
          <Checkbox
            label={t("setup.hide_powered_by", "Hide \"Powered by COD King\"")}
            checked={!!(general.branding && general.branding.hide_powered_by)}
            onChange={(value) => onChange(["branding", "hide_powered_by"], value)}
          />
        </Gate>
      </BlockStack>
    </SectionCard>
  );
};

export default AdvancedCard;
