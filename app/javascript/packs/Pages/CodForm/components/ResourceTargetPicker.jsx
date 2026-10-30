import React, { useCallback, useState } from "react";
import { BlockStack, InlineStack, Button, Tag, Text, InlineError } from "@shopify/polaris";
import { useAppBridge } from "@shopify/app-bridge-react";
import { t } from "../i18n";

/* Ids are stored as numeric strings (0.1); the picker works with GIDs. */
const GID_TYPE = { product: "Product", collection: "Collection", variant: "ProductVariant" };
const TITLE_CACHE_KEY = "codkf_resource_titles";

const readTitles = () => {
  try {
    return JSON.parse(window.sessionStorage.getItem(TITLE_CACHE_KEY) || "{}") || {};
  } catch (_) {
    return {};
  }
};

const rememberTitles = (type, items) => {
  try {
    const titles = readTitles();
    items.forEach((item) => {
      const id = String(item.id).split("/").pop();
      const title = item.displayName || item.title;
      if (title) titles[`${type}:${id}`] = title;
    });
    window.sessionStorage.setItem(TITLE_CACHE_KEY, JSON.stringify(titles));
  } catch (_) {
    /* storage unavailable: tags fall back to the id */
  }
};

export const resourceTitle = (type, id) => readTitles()[`${type}:${id}`] || `#${id}`;

/**
 * Product / collection / variant targeting with the App Bridge v4 resource
 * picker (`shopify.resourcePicker`), the idiom used by the partial-payment
 * rule editor. The picker returns the final checked set, so it replaces `ids`.
 */
const ResourceTargetPicker = ({ type = "product", ids, onChange, label, buttonLabel, multiple = true, disabled, helpText }) => {
  const shopify = useAppBridge();
  const [error, setError] = useState(null);
  const list = (Array.isArray(ids) ? ids : ids ? [ids] : []).map(String);

  const open = useCallback(async () => {
    try {
      const selected = await shopify.resourcePicker({
        type,
        multiple,
        action: "select",
        selectionIds: list.map((id) => ({ id: `gid://shopify/${GID_TYPE[type]}/${id}` })),
        filter: type === "variant" ? undefined : { variants: false },
      });
      if (selected) {
        let items = Array.from(selected);
        // A product pick used for variants returns products with their variants.
        if (type === "variant") {
          items = items.reduce(
            (all, item) => all.concat(Array.isArray(item.variants) && item.variants.length ? item.variants : [item]),
            [],
          );
        }
        rememberTitles(type, items);
        const next = [...new Set(items.map((item) => String(item.id).split("/").pop()))];
        onChange(multiple ? next : next.slice(0, 1));
        setError(null);
      }
    } catch (err) {
      console.error("Resource picker error:", err);
      setError(t("common.picker_error", "The picker could not be opened. Try again."));
    }
  }, [shopify, type, multiple, list, onChange]);

  const defaultButton =
    type === "collection"
      ? t("common.select_collections", "Select collections")
      : type === "variant"
      ? t("common.select_variants", "Select variants")
      : t("common.select_products", "Select products");

  return (
    <BlockStack gap="200">
      {label && (
        <Text as="p" variant="bodyMd">
          {label}
        </Text>
      )}
      <InlineStack gap="200" blockAlign="center" wrap>
        <Button onClick={open} disabled={disabled}>
          {buttonLabel || defaultButton}
        </Button>
        {list.length > 0 && (
          <Text as="span" variant="bodySm" tone="subdued">
            {t("common.selected_count", "%{count} selected", { count: list.length })}
          </Text>
        )}
      </InlineStack>
      {list.length > 0 && (
        <InlineStack gap="200" wrap>
          {list.slice(0, 30).map((id) => (
            <Tag key={id} disabled={disabled} onRemove={() => onChange(list.filter((item) => item !== id))}>
              {resourceTitle(type, id)}
            </Tag>
          ))}
          {list.length > 30 && (
            <Text as="span" variant="bodySm" tone="subdued">
              {t("common.and_more", "and %{count} more", { count: list.length - 30 })}
            </Text>
          )}
        </InlineStack>
      )}
      {helpText && (
        <Text as="p" variant="bodySm" tone="subdued">
          {helpText}
        </Text>
      )}
      {error && <InlineError message={error} fieldID="codkf-resource-picker" />}
    </BlockStack>
  );
};

export default ResourceTargetPicker;
