import React from "react";
import styled from "styled-components";
import { Badge, Banner, BlockStack, Checkbox, ChoiceList, InlineGrid, Select, Text, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import LocalizedTextField from "../components/LocalizedTextField";
import MoneyField from "../components/MoneyField";
import ResourceTargetPicker, { resourceTitle } from "../components/ResourceTargetPicker";
import { toInt } from "../utils";
import { t } from "../i18n";
import OfferEditorShell from "./OfferEditorShell";
import DiscountFields from "./DiscountFields";

export const PRE_UPSELL_DISCOUNTS = ["none", "percentage", "fixed_amount", "fixed_price"];

const validate = (offer) => {
  const config = offer.config || {};
  const problems = [];
  if (!config.title || !config.title.default) problems.push(t("offers.error_offer_title", "Enter a title."));
  if (config.source === "collection" && !config.collection_id) {
    problems.push(t("offers.error_pre_upsell_collection", "Select the collection to offer."));
  }
  if (config.source !== "collection" && !(config.product_ids || []).length) {
    problems.push(t("offers.error_pre_upsell_products", "Select at least one product to offer."));
  }
  if (config.discount_type === "percentage" && !(Number(config.value) >= 0 && Number(config.value) <= 100)) {
    problems.push(t("offers.error_tier_percent", "A percentage must be between 0 and 100."));
  }
  if (config.min_cart_cents && config.max_cart_cents && config.max_cart_cents < config.min_cart_cents) {
    problems.push(t("offers.error_pre_upsell_range", "The maximum cart value must be more than the minimum."));
  }
  return problems;
};

/* A small likeness of the storefront popup: the merchant's texts, the chosen products. */
const Mock = styled.div`
  max-width: 360px;
  margin: 0 auto;
  border: 1px solid var(--p-color-border, #e3e3e3);
  border-radius: 14px;
  padding: 16px;
  background: #fff;
  display: flex;
  flex-direction: column;
  gap: 10px;
  font-size: 13px;
  h4 {
    margin: 0;
    font-size: 16px;
    text-align: center;
  }
  p {
    margin: 0;
    color: #6d7175;
    text-align: center;
  }
  .row {
    display: flex;
    gap: 10px;
    align-items: center;
    padding: 8px;
    border: 1px solid #e3e3e3;
    border-radius: 10px;
  }
  .img {
    width: 44px;
    height: 44px;
    border-radius: 8px;
    background: #f1f1f1;
    flex: none;
  }
  .name {
    flex: 1;
    min-width: 0;
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .add {
    width: 28px;
    height: 28px;
    border-radius: 50%;
    border: 1.5px solid #1a1a1a;
    display: grid;
    place-items: center;
    flex: none;
  }
  .btn {
    background: #1a1a1a;
    color: #fff;
    border-radius: 8px;
    padding: 10px;
    text-align: center;
    font-weight: 600;
  }
  .lnk {
    text-align: center;
    text-decoration: underline;
    font-weight: 600;
  }
`;

const discountBadge = (config) => {
  const value = Number(config.value) || 0;
  switch (config.discount_type) {
    case "percentage":
      return value > 0 ? t("offers.pre_upsell_badge_percent", "%{value}% off", { value }) : null;
    case "fixed_amount":
      return value > 0 ? t("offers.pre_upsell_badge_amount", "%{value} off", { value: (value / 100).toFixed(2) }) : null;
    case "fixed_price":
      return t("offers.pre_upsell_badge_price", "Only %{value}", { value: (value / 100).toFixed(2) });
    default:
      return null;
  }
};

const PopupPreview = ({ config }) => {
  const inline = config.display === "inline";
  const names =
    config.source === "collection"
      ? Array.from({ length: Math.min(config.max_products || 3, 3) }, (_, index) =>
          t("offers.pre_upsell_preview_item", "Product %{n} from %{collection}", {
            n: index + 1,
            collection: config.collection_id ? resourceTitle("collection", config.collection_id) : "…",
          }),
        )
      : (config.product_ids || []).slice(0, Math.min(config.max_products || 3, 6)).map((id) => resourceTitle("product", id));
  const single = names.length === 1;
  const badge = discountBadge(config);
  return (
    <Mock aria-hidden="true">
      <h4>{(config.title && config.title.default) || "…"}</h4>
      {config.body && config.body.default && <p>{config.body.default}</p>}
      {config.timer_seconds > 0 && <p style={{ color: "#d72c0d", fontWeight: 600 }}>{t("offers.pre_upsell_preview_timer", "Offer ends in %{seconds}s", { seconds: config.timer_seconds })}</p>}
      {(names.length ? names : ["…"]).map((name, index) => (
        <div className="row" key={index}>
          <span className="img" />
          <span className="name">{name}</span>
          {badge && <Badge tone="success">{badge}</Badge>}
          {(!single || inline) && <span className="add">+</span>}
        </div>
      ))}
      {!inline && (
        <>
          <div className="btn">{(config.accept_label && config.accept_label.default) || t("offers.pre_upsell_accept_default", "Add to my order")}</div>
          <div className="lnk">{(config.decline_label && config.decline_label.default) || t("offers.pre_upsell_decline_default", "No thanks, complete my order")}</div>
        </>
      )}
    </Mock>
  );
};

/**
 * Pre-purchase upsell rule: "If the cart has" these products / collections (and a cart value),
 * "Then offer" these products or a collection, with or without a discount, in a popup shown
 * after "Complete order" and before the order is placed. Several rules can be active; the
 * matching rule with the lowest priority number is shown.
 */
const PreUpsellEditor = ({ segment, id }) => (
  <OfferEditorShell segment={segment} id={id} validate={validate} hideTargeting>
    {({ offer, config, setConfig, setData }) => {
      const targeting = offer.targeting || { scope: "all", product_ids: [], collection_ids: [] };
      const setTargeting = (patch) => setData((current) => ({ ...current, targeting: { ...targeting, ...patch } }));
      const selected = targeting.scope === "selected";
      const fromCollection = config.source === "collection";
      return (
        <>
          <SectionCard
            title={t("offers.pre_upsell_if_title", "If the cart has")}
            description={t("offers.pre_upsell_if_help", "When this rule applies. Products already in the cart are never offered again.")}
          >
            <BlockStack gap="400">
              <ChoiceList
                title={t("offers.pre_upsell_if_title", "If the cart has")}
                titleHidden
                choices={[
                  { label: t("offers.pre_upsell_if_any", "Any product"), value: "all" },
                  { label: t("offers.pre_upsell_if_selected", "Specific products or collections"), value: "selected" },
                ]}
                selected={[selected ? "selected" : "all"]}
                onChange={(next) => setTargeting({ scope: next[0] })}
              />
              {selected && (
                <>
                  <InlineGrid columns={{ xs: 1, md: 2 }} gap="400">
                    <ResourceTargetPicker
                      type="product"
                      label={t("common.products", "Products")}
                      ids={targeting.product_ids}
                      onChange={(ids) => setTargeting({ product_ids: ids })}
                    />
                    <ResourceTargetPicker
                      type="collection"
                      label={t("common.collections", "Collections")}
                      ids={targeting.collection_ids}
                      onChange={(ids) => setTargeting({ collection_ids: ids })}
                    />
                  </InlineGrid>
                  <ChoiceList
                    title={t("offers.pre_upsell_match", "Show when the cart has")}
                    choices={[
                      { label: t("offers.pre_upsell_match_any", "Any of these"), value: "any" },
                      { label: t("offers.pre_upsell_match_all", "All of these"), value: "all" },
                    ]}
                    selected={[config.match === "all" ? "all" : "any"]}
                    onChange={(next) => setConfig("match", next[0])}
                  />
                </>
              )}
              <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                <MoneyField
                  label={t("offers.pre_upsell_min_cart", "Minimum cart value (optional)")}
                  value={config.min_cart_cents}
                  onChange={(cents) => setConfig("min_cart_cents", cents)}
                />
                <MoneyField
                  label={t("offers.pre_upsell_max_cart", "Maximum cart value (optional)")}
                  value={config.max_cart_cents}
                  onChange={(cents) => setConfig("max_cart_cents", cents)}
                />
              </InlineGrid>
            </BlockStack>
          </SectionCard>

          <SectionCard
            title={t("offers.pre_upsell_then_title", "Then offer")}
            description={t("offers.pre_upsell_then_help", "Out-of-stock products and products already in the cart are skipped.")}
          >
            <BlockStack gap="400">
              <ChoiceList
                title={t("offers.pre_upsell_then_title", "Then offer")}
                titleHidden
                choices={[
                  { label: t("offers.pre_upsell_source_products", "Specific products"), value: "products" },
                  { label: t("offers.pre_upsell_source_collection", "Products from a collection"), value: "collection" },
                ]}
                selected={[fromCollection ? "collection" : "products"]}
                onChange={(next) => setConfig("source", next[0])}
              />
              {fromCollection ? (
                <ResourceTargetPicker
                  type="collection"
                  multiple={false}
                  label={t("offers.pre_upsell_collection", "Collection")}
                  buttonLabel={config.collection_id ? t("offers.change_collection", "Change collection") : t("offers.select_collection", "Select collection")}
                  ids={config.collection_id ? [String(config.collection_id)] : []}
                  onChange={(ids) => setConfig("collection_id", ids[0] ? String(ids[0]) : null)}
                  helpText={t("offers.pre_upsell_collection_help", "The first products of the collection, in the collection's own order.")}
                />
              ) : (
                <ResourceTargetPicker
                  type="product"
                  label={t("offers.pre_upsell_products", "Products to offer")}
                  ids={config.product_ids}
                  onChange={(ids) => setConfig("product_ids", ids)}
                  helpText={t("offers.pre_upsell_products_help", "Shown in this order. The buyer picks the variant (size, colour).")}
                />
              )}
              <TextField
                label={t("offers.pre_upsell_max_products", "Products shown at most")}
                type="number"
                min={1}
                max={6}
                value={String(config.max_products || 3)}
                onChange={(value) => setConfig("max_products", Math.min(6, Math.max(1, toInt(value, 3))))}
                helpText={t("offers.pre_upsell_max_products_help", "1 shows one large card; 2 to 6 show a list with an Add button on each product.")}
                autoComplete="off"
              />
              <DiscountFields
                types={PRE_UPSELL_DISCOUNTS}
                type={config.discount_type || "none"}
                value={config.value}
                onTypeChange={(next) => setData((current) => ({ ...current, config: { ...current.config, discount_type: next, value: next === "percentage" ? 10 : 0 } }))}
                onValueChange={(value) => setConfig("value", value)}
                valueLabel={config.discount_type === "fixed_price" ? t("offers.pre_upsell_fixed_price", "Price per item") : undefined}
              />
              {config.discount_type === "fixed_price" && (
                <Text as="p" variant="bodySm" tone="subdued">
                  {t("offers.pre_upsell_fixed_price_help", "Products that already cost less keep their own price.")}
                </Text>
              )}
              <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                <Checkbox
                  label={t("offers.pre_upsell_quantity_picker", "Let the buyer choose a quantity")}
                  checked={!!config.quantity_picker}
                  onChange={(value) => setConfig("quantity_picker", value)}
                />
                {config.quantity_picker && (
                  <TextField
                    label={t("offers.pre_upsell_max_quantity", "Maximum quantity per product")}
                    type="number"
                    min={1}
                    max={10}
                    value={String(config.max_quantity || 3)}
                    onChange={(value) => setConfig("max_quantity", Math.min(10, Math.max(1, toInt(value, 3))))}
                    autoComplete="off"
                  />
                )}
              </InlineGrid>
            </BlockStack>
          </SectionCard>

          <SectionCard
            title={t("offers.pre_upsell_display_title", "Where to show it")}
            description={t("offers.pre_upsell_display_help", "In a popup after Complete order, or as a section inside the form that the buyer can add from while filling it in.")}
          >
            <InlineGrid columns={{ xs: 1, md: 2 }} gap="500">
              <BlockStack gap="400">
                <ChoiceList
                  title={t("offers.pre_upsell_display_title", "Where to show it")}
                  titleHidden
                  choices={[
                    {
                      label: t("offers.pre_upsell_display_popup", "Popup after Complete order"),
                      value: "popup",
                      helpText: t("offers.pre_upsell_display_popup_help", "Shown once, before the order is placed."),
                    },
                    {
                      label: t("offers.pre_upsell_display_inline", "Inside the form"),
                      value: "inline",
                      helpText: t("offers.pre_upsell_display_inline_help", "A section with an Add button on each product; the total updates at once."),
                    },
                  ]}
                  selected={[config.display === "inline" ? "inline" : "popup"]}
                  onChange={(next) => setConfig("display", next[0])}
                />
                {config.display === "inline" && (
                  <Select
                    label={t("offers.pre_upsell_position", "Position in the form")}
                    options={[
                      { value: "after_summary", label: t("offers.bump_position_after_summary", "After the order summary") },
                      { value: "before_shipping", label: t("offers.bump_position_before_shipping", "Before the shipping method") },
                      { value: "before_totals", label: t("offers.bump_position_before_totals", "Before the totals") },
                    ]}
                    value={config.position || "before_totals"}
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
                {config.display !== "inline" && (
                <>
                <LocalizedTextField
                  label={t("offers.accept_label", "Accept button")}
                  value={config.accept_label}
                  onChange={(value) => setConfig("accept_label", value)}
                  maxLength={60}
                />
                <LocalizedTextField
                  label={t("offers.decline_label", "Decline link")}
                  value={config.decline_label}
                  onChange={(value) => setConfig("decline_label", value)}
                  maxLength={60}
                />
                </>
                )}
                {config.display !== "inline" && (
                <TextField
                  label={t("offers.pre_upsell_timer", "Countdown (seconds, 0 = none)")}
                  type="number"
                  min={0}
                  value={String(config.timer_seconds || 0)}
                  onChange={(value) => setConfig("timer_seconds", Math.max(0, toInt(value, 0)))}
                  helpText={t("offers.pre_upsell_timer_help", "Only for urgency: when it ends, the offer stays.")}
                  autoComplete="off"
                />
                )}
              </BlockStack>
              <BlockStack gap="200">
                <Text as="h4" variant="headingSm">
                  {t("offers.preview", "Preview")}
                </Text>
                <PopupPreview config={config} />
                {offer.id && config.candidates_refreshed_at && !(config.candidates || []).length && (
                  <Banner tone="warning">
                    <p>{t("offers.pre_upsell_no_candidates", "None of these products can be offered right now (draft, archived or gift cards).")}</p>
                  </Banner>
                )}
              </BlockStack>
            </InlineGrid>
          </SectionCard>
        </>
      );
    }}
  </OfferEditorShell>
);

export default PreUpsellEditor;
