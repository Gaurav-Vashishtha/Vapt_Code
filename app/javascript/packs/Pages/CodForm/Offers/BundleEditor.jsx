import React from "react";
import styled from "styled-components";
import { Badge, Banner, BlockStack, Checkbox, InlineGrid, Select, Text, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import LocalizedTextField from "../components/LocalizedTextField";
import ResourceTargetPicker, { resourceTitle } from "../components/ResourceTargetPicker";
import { t } from "../i18n";
import OfferEditorShell from "./OfferEditorShell";
import DiscountFields from "./DiscountFields";

const BUNDLE_DISCOUNTS = ["none", "percentage", "fixed_amount", "fixed_price"];

const validate = (offer) => {
  const config = offer.config || {};
  const problems = [];
  const count = (config.product_ids || []).length;
  if (count < 2 || count > 6) problems.push(t("offers.error_bundle_products", "A bundle needs 2 to 6 products."));
  if (!config.title || !config.title.default) problems.push(t("offers.error_offer_title", "Enter a title."));
  if (!config.show_on_product_page && !config.show_in_form) {
    problems.push(t("offers.error_bundle_place", "Show the bundle on the product page, in the form, or both."));
  }
  if (config.discount_type === "percentage" && !(Number(config.value) >= 0 && Number(config.value) <= 100)) {
    problems.push(t("offers.error_tier_percent", "A percentage must be between 0 and 100."));
  }
  return problems;
};

const Mock = styled.div`
  max-width: 360px;
  margin: 0 auto;
  border: 1px solid #e3e3e3;
  border-radius: 12px;
  padding: 14px;
  background: #fff;
  display: flex;
  flex-direction: column;
  gap: 8px;
  font-size: 13px;
  b.title {
    font-size: 15px;
  }
  .row {
    display: flex;
    gap: 8px;
    align-items: center;
    padding: 8px;
    border: 1px solid #ececec;
    border-radius: 8px;
  }
  .box {
    width: 14px;
    height: 14px;
    border-radius: 3px;
    background: #1a1a1a;
    flex: none;
  }
  .img {
    width: 36px;
    height: 36px;
    border-radius: 6px;
    background: #f1f1f1;
    flex: none;
  }
  .name {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-weight: 600;
  }
  .plus {
    text-align: center;
    color: #8a8a8a;
    font-weight: 700;
    line-height: 1;
  }
  .btn {
    background: #1a1a1a;
    color: #fff;
    border-radius: 8px;
    padding: 10px;
    text-align: center;
    font-weight: 600;
  }
`;

const badgeText = (config) => {
  const value = Number(config.value) || 0;
  switch (config.discount_type) {
    case "percentage":
      return value > 0 ? t("offers.pre_upsell_badge_percent", "%{value}% off", { value }) : null;
    case "fixed_amount":
      return value > 0 ? t("offers.pre_upsell_badge_amount", "%{value} off", { value: (value / 100).toFixed(2) }) : null;
    case "fixed_price":
      return t("offers.bundle_badge_price", "Set price %{value}", { value: (value / 100).toFixed(2) });
    default:
      return null;
  }
};

const Preview = ({ config }) => {
  const ids = (config.product_ids || []).slice(0, 6);
  const badge = badgeText(config);
  return (
    <Mock aria-hidden="true">
      <b className="title">{(config.title && config.title.default) || "…"}</b>
      {config.body && config.body.default && <span style={{ color: "#6d7175" }}>{config.body.default}</span>}
      {(ids.length ? ids : ["", ""]).map((id, index) => (
        <React.Fragment key={id || index}>
          {index > 0 && <div className="plus">+</div>}
          <div className="row">
            <span className="box" />
            <span className="img" />
            <span className="name">{id ? resourceTitle("product", id) : "…"}</span>
          </div>
        </React.Fragment>
      ))}
      {badge && (
        <div>
          <Badge tone="success">{badge}</Badge>
        </div>
      )}
      <div className="btn">{(config.button_label && config.button_label.default) || t("offers.bundle_button_default", "Buy the set with COD")}</div>
    </Mock>
  );
};

/**
 * Bundle: 2 to 6 products sold together with a discount on the set. Shown on the product page
 * of each of its products (a "Frequently bought together" box with its own COD button) and / or
 * inside the form when the cart has some of its products. The buyer picks the variants and can
 * untick products; the discount applies once every product of the bundle is in the order.
 */
const BundleEditor = ({ segment, id }) => (
  <OfferEditorShell segment={segment} id={id} validate={validate} hideTargeting>
    {({ offer, config, setConfig, setData }) => (
      <>
        <SectionCard
          title={t("offers.bundle_products_title", "Products in the bundle")}
          description={t("offers.bundle_products_help", "2 to 6 products, shown in this order. The buyer picks the variant (size, colour) of each.")}
        >
          <BlockStack gap="400">
            <ResourceTargetPicker
              type="product"
              label={t("common.products", "Products")}
              ids={config.product_ids}
              onChange={(ids) => setConfig("product_ids", ids.slice(0, 6))}
            />
            <DiscountFields
              types={BUNDLE_DISCOUNTS}
              type={config.discount_type || "none"}
              value={config.value}
              onTypeChange={(next) => setData((current) => ({ ...current, config: { ...current.config, discount_type: next, value: next === "percentage" ? 10 : 0 } }))}
              onValueChange={(value) => setConfig("value", value)}
              valueLabel={config.discount_type === "fixed_price" ? t("offers.bundle_fixed_price", "Price of the whole set") : config.discount_type === "fixed_amount" ? t("offers.bundle_amount_off", "Amount off the set") : undefined}
            />
            <Text as="p" variant="bodySm" tone="subdued">
              {t("offers.bundle_discount_help", "The discount applies to each complete set in the order: one of every product of the bundle. Buyers can leave products out, at the regular price.")}
            </Text>
          </BlockStack>
        </SectionCard>

        <SectionCard
          title={t("offers.bundle_where_title", "Where to show it")}
          description={t("offers.bundle_where_help", "Choose one or both.")}
        >
          <InlineGrid columns={{ xs: 1, md: 2 }} gap="500">
            <BlockStack gap="400">
              <Checkbox
                label={t("offers.bundle_on_product_page", "On the product page")}
                helpText={t("offers.bundle_on_product_page_help", "On the page of each product of the bundle, below the COD button, with its own button that opens the form with the whole set.")}
                checked={config.show_on_product_page !== false}
                onChange={(value) => setConfig("show_on_product_page", value)}
              />
              {config.show_on_product_page !== false && (
                <>
                  <Select
                    label={t("offers.bundle_page_position", "Position on the product page")}
                    options={[
                      { value: "above_button", label: t("offers.bundle_page_above", "Above the COD button") },
                      { value: "below_button", label: t("offers.bundle_page_below", "Below the COD button") },
                      { value: "before_element", label: t("offers.bundle_page_before_element", "Before an element of my theme") },
                      { value: "after_element", label: t("offers.bundle_page_after_element", "After an element of my theme") },
                    ]}
                    value={config.page_position || "above_button"}
                    onChange={(value) => setConfig("page_position", value)}
                  />
                  {(config.page_position === "before_element" || config.page_position === "after_element") && (
                    <TextField
                      label={t("offers.bundle_page_selector", "Element (CSS selector)")}
                      value={config.page_selector || ""}
                      onChange={(value) => setConfig("page_selector", value)}
                      placeholder=".product__description"
                      helpText={t("offers.bundle_page_selector_help", "For example .product__description or #product-info. When it is not found, the bundle shows above the COD button.")}
                      autoComplete="off"
                    />
                  )}
                </>
              )}
              <Checkbox
                label={t("offers.bundle_in_form", "Inside the COD form")}
                helpText={t("offers.bundle_in_form_help", "When the cart has some of the bundle's products: one tap adds the missing ones.")}
                checked={config.show_in_form !== false}
                onChange={(value) => setConfig("show_in_form", value)}
              />
              {config.show_in_form !== false && (
                <Select
                  label={t("offers.pre_upsell_position", "Position in the form")}
                  options={[
                    { value: "after_summary", label: t("offers.bump_position_after_summary", "After the order summary") },
                    { value: "before_shipping", label: t("offers.bump_position_before_shipping", "Before the shipping method") },
                    { value: "before_totals", label: t("offers.bump_position_before_totals", "Before the totals") },
                  ]}
                  value={config.position || "after_summary"}
                  onChange={(value) => setConfig("position", value)}
                />
              )}
              <LocalizedTextField
                label={t("offers.offer_title", "Title")}
                value={config.title}
                onChange={(value) => setConfig("title", value)}
                maxLength={120}
              />
              <LocalizedTextField
                label={t("offers.offer_body", "Text (optional)")}
                value={config.body}
                onChange={(value) => setConfig("body", value)}
                multiline={2}
              />
              <LocalizedTextField
                label={t("offers.bundle_button", "Product page button (optional)")}
                value={config.button_label}
                onChange={(value) => setConfig("button_label", value)}
                maxLength={60}
                helpText={t("offers.bundle_button_help", "Empty: the COD button's own label. The set price is added after it.")}
              />
            </BlockStack>
            <BlockStack gap="200">
              <Text as="h4" variant="headingSm">
                {t("offers.preview", "Preview")}
              </Text>
              <Preview config={config} />
              {offer.id && config.candidates_refreshed_at && (config.candidates || []).length < (config.product_ids || []).length && (
                <Banner tone="warning">
                  <p>{t("offers.bundle_unavailable", "Some products of this bundle are draft, archived or gift cards: the bundle is not shown until every product can be sold.")}</p>
                </Banner>
              )}
            </BlockStack>
          </InlineGrid>
        </SectionCard>
      </>
    )}
  </OfferEditorShell>
);

export default BundleEditor;
