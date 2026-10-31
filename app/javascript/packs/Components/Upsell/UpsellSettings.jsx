import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActionList,
  Badge,
  Banner,
  BlockStack,
  Box,
  Button,
  Card,
  Checkbox,
  Collapsible,
  InlineStack,
  Layout,
  Page,
  Popover,
  Select,
  Spinner,
  Tabs,
  Text,
  Thumbnail,
  Tooltip,
  Icon,
} from "@shopify/polaris";
import { DeleteMinor, HorizontalDotsMinor, ImageMajor, InfoMinor } from "@shopify/polaris-icons";
import { SaveBar } from "@shopify/app-bridge-react";
import styled from "styled-components";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import SortableList from "../../Pages/CodForm/Designer/SortableList";
import FeatureCallout from "../FeatureCallout";
import { SectionCard, SettingRow } from "../SettingsPrimitives";
import { navigateTo } from "../../../utils/navigate";

const t = (key, fallback, opts = {}) => I18n.t(`upsell.${key}`, { defaultValue: fallback, ...opts });

const numericId = (gid) => Number(String(gid).split("/").pop());
const productGid = (id) => `gid://shopify/Product/${id}`;
const variantGid = (id) => `gid://shopify/ProductVariant/${id}`;
const collectionGid = (id) => `gid://shopify/Collection/${id}`;

const EMPTY_FORM = {
  enabled: false,
  maxItems: 5,
  showQuantitySelector: false,
  verticalLayout: false,
  products: [],
  collections: [],
};

const moveItem = (list, from, to) => {
  const next = [...list];
  const [item] = next.splice(from, 1);
  next.splice(to, 0, item);
  return next;
};

const productRow = (product, variantIds = [], autoAdd = false) => {
  const variants = product.variants || [];
  const chosen = variantIds.length ? variants.filter((v) => variantIds.includes(v.id)) : variants;
  return {
    id: product.id,
    title: product.title,
    image: product.image,
    status: product.status,
    totalInventory: product.totalInventory,
    totalVariants: product.variantsCount ?? variants.length,
    variants: chosen,
    allSelected: variantIds.length === 0,
    autoAdd,
  };
};

const pickerProductRow = (picked) => {
  const totalVariants = picked.totalVariants ?? picked.variants?.length ?? 0;
  const variants = (picked.variants || []).map((v) => ({
    id: numericId(v.id),
    title: v.title,
    inventoryQuantity: v.inventoryQuantity,
  }));
  return {
    id: numericId(picked.id),
    title: picked.title,
    image: picked.images?.[0]?.originalSrc || picked.images?.[0]?.url || null,
    status: picked.status,
    totalInventory: picked.totalInventory,
    totalVariants,
    variants,
    allSelected: variants.length >= totalVariants,
  };
};

const pickerCollectionRow = (picked) => ({
  id: numericId(picked.id),
  title: picked.title,
  image: picked.image?.originalSrc || picked.image?.url || null,
  productsCount: picked.productsCount ?? null,
});

const toForm = (data) => {
  const config = data?.config;
  if (!config) return EMPTY_FORM;
  const products = Object.fromEntries((data.products || []).map((p) => [p.id, p]));
  const collections = Object.fromEntries((data.collections || []).map((c) => [c.id, c]));
  const items = config.items || [];
  return {
    enabled: config.enabled === true,
    maxItems: config.maxItems || 5,
    showQuantitySelector: config.showQuantitySelector === true,
    verticalLayout: config.verticalLayout === true,
    products: items
      .filter((i) => i.type === "product" && products[i.shopifyId])
      .map((i) => productRow(products[i.shopifyId], i.variantIds || [], i.autoAdd === true)),
    collections: items
      .filter((i) => i.type === "collection" && collections[i.shopifyId])
      .map((i) => collections[i.shopifyId]),
  };
};

const toConfig = (form) => ({
  enabled: form.enabled,
  maxItems: form.maxItems,
  showQuantitySelector: form.showQuantitySelector,
  verticalLayout: form.verticalLayout,
  items: [
    ...form.products.map((p) => ({
      type: "product",
      shopifyId: p.id,
      variantIds: p.allSelected ? [] : p.variants.map((v) => v.id),
      autoAdd: p.autoAdd === true,
    })),
    ...form.collections.map((c) => ({ type: "collection", shopifyId: c.id, variantIds: [] })),
  ].map((item, position) => ({ ...item, position })),
});

const TableRow = styled.div`
  display: grid;
  grid-template-columns: minmax(0, 1fr) 88px 64px 96px 36px;
  align-items: center;
  gap: 12px;
`;

const Switch = styled.button`
  position: relative;
  width: 36px;
  height: 20px;
  padding: 0;
  border: 0;
  border-radius: 999px;
  background: ${(p) => (p.$on ? "var(--p-color-bg-fill-brand, #303030)" : "var(--p-color-bg-fill-tertiary, #e3e3e3)")};
  cursor: pointer;
  transition: background 150ms ease;

  &::after {
    content: "";
    position: absolute;
    top: 2px;
    left: ${(p) => (p.$on ? "18px" : "2px")};
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: #fff;
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.2);
    transition: left 150ms ease;
  }

  &:focus-visible {
    outline: 2px solid var(--p-color-border-focus, #005bd3);
    outline-offset: 2px;
  }
`;

function ProductTableHeader() {
  const head = (text) => (
    <Text as="span" variant="bodySm" fontWeight="semibold" tone="subdued">
      {text}
    </Text>
  );
  return (
    <TableRow>
      {head(t("col_product", "Product"))}
      {head(t("col_status", "Status"))}
      {head(t("col_variants", "Variants"))}
      <InlineStack gap="100" blockAlign="center" wrap={false}>
        {head(t("col_auto_add", "Auto add"))}
        <Tooltip
          content={t(
            "auto_add_info",
            "Adds this product to the cart automatically (qty 1). Customers can still remove it."
          )}
          width="wide"
        >
          <span tabIndex={0} aria-label={t("auto_add_info_label", "What is auto add?")} style={{ display: "inline-flex", cursor: "help" }}>
            <Icon source={InfoMinor} tone="subdued" />
          </span>
        </Tooltip>
      </InlineStack>
      <span />
    </TableRow>
  );
}

const statusTone = (status) => (status === "ACTIVE" ? "success" : status === "DRAFT" ? "info" : undefined);

function ProductRow({ row, onEdit, onRemove, onRemoveVariant, onAutoAddChange }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [expanded, setExpanded] = useState(false);
  return (
    <BlockStack gap="200">
      <TableRow>
        <InlineStack gap="300" blockAlign="center" wrap={false}>
          <Thumbnail source={row.image || ImageMajor} alt={row.title} size="small" />
          <BlockStack gap="100">
            <Button variant="plain" onClick={() => setExpanded((v) => !v)} textAlign="left">
              {row.title}
            </Button>
            <Text as="span" tone="subdued" variant="bodySm">
              {t("stock", "%{count} in stock for %{variants} variants", {
                count: row.totalInventory ?? 0,
                variants: row.totalVariants,
              })}
            </Text>
          </BlockStack>
        </InlineStack>
        <div>{row.status && <Badge tone={statusTone(row.status)}>{row.status.charAt(0) + row.status.slice(1).toLowerCase()}</Badge>}</div>
        <Text as="span" variant="bodySm">
          {row.variants.length}/{row.totalVariants}
        </Text>
        <Switch
          type="button"
          role="switch"
          aria-checked={row.autoAdd === true}
          aria-label={t("auto_add_label", "Auto-add %{title} to cart", { title: row.title })}
          title={t("auto_add_help", "Added once, qty 1, using the first in-stock variant.")}
          $on={row.autoAdd === true}
          onClick={() => onAutoAddChange(!(row.autoAdd === true))}
        />
        <Popover
          active={menuOpen}
          onClose={() => setMenuOpen(false)}
          activator={<Button icon={HorizontalDotsMinor} variant="tertiary" accessibilityLabel={t("actions", "Actions")} onClick={() => setMenuOpen((v) => !v)} />}
        >
          <ActionList
            actionRole="menuitem"
            items={[
              { content: t("edit", "Edit"), onAction: () => { setMenuOpen(false); onEdit(); } },
              { content: t("remove", "Remove"), destructive: true, onAction: () => { setMenuOpen(false); onRemove(); } },
            ]}
          />
        </Popover>
      </TableRow>
      <Collapsible open={expanded} id={`upsell-variants-${row.id}`}>
        <Box paddingInlineStart="1200">
          <BlockStack gap="100">
            {row.variants.map((variant) => (
              <InlineStack key={variant.id} align="space-between" blockAlign="center">
                <Text as="span" variant="bodySm">
                  {variant.title}
                  {variant.inventoryQuantity != null ? ` · ${t("in_stock", "%{count} in stock", { count: variant.inventoryQuantity })}` : ""}
                </Text>
                <Button
                  icon={DeleteMinor}
                  variant="tertiary"
                  tone="critical"
                  accessibilityLabel={t("remove_variant", "Remove variant")}
                  onClick={() => onRemoveVariant(variant.id)}
                />
              </InlineStack>
            ))}
          </BlockStack>
        </Box>
      </Collapsible>
    </BlockStack>
  );
}

function FreeGiftCard() {
  const [config, setConfig] = useState(null);

  useEffect(() => {
    Api.get("/free_gift_config")
      .then((res) => setConfig(res.data?.config || null))
      .catch(() => setConfig(null));
  }, []);

  const rules = config?.rules || [];
  const activeRules = rules.filter((rule) => rule.enabled).length;

  return (
    <Card>
      <InlineStack align="space-between" blockAlign="center" gap="400" wrap={false}>
        <BlockStack gap="100">
          <InlineStack gap="200" blockAlign="center">
            <Text as="h3" variant="headingMd">
              {t("free_gift_title", "Free gifts")}
            </Text>
            {config?.enabled ? (
              <Badge tone="success">{t("free_gift_on", "On")}</Badge>
            ) : (
              <Badge>{t("free_gift_off", "Off")}</Badge>
            )}
          </InlineStack>
          <Text as="p" tone="subdued">
            {t("free_gift_help", "Auto-add a free product by cart value, cart items, products or collections.")}
          </Text>
          {config && (
            <Text as="p" variant="bodySm" tone="subdued">
              {t("free_gift_rules_count", "%{active} of %{total} rules active", { active: activeRules, total: rules.length })}
            </Text>
          )}
        </BlockStack>
        <Button onClick={() => navigateTo("/features/upsell/free-gift")}>{t("free_gift_configure", "Configure")}</Button>
      </InlineStack>
    </Card>
  );
}

export default function UpsellSettings() {
  const [saved, setSaved] = useState(EMPTY_FORM);
  const [form, setForm] = useState(EMPTY_FORM);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [tab, setTab] = useState(0);

  useEffect(() => {
    Api.get("/upsell_config")
      .then((res) => {
        const next = toForm(res.data);
        setSaved(next);
        setForm(next);
      })
      .catch(() => setError(t("load_error", "Could not load upsell settings.")))
      .finally(() => setLoading(false));
  }, []);

  const isDirty = useMemo(() => JSON.stringify(toConfig(form)) !== JSON.stringify(toConfig(saved)), [form, saved]);
  const update = (patch) => setForm((f) => ({ ...f, ...patch }));

  const handleSave = useCallback(async () => {
    setSaving(true);
    setError("");
    try {
      const res = await Api.post("/upsell_config", { upsellConfig: toConfig(form) });
      const next = toForm(res.data);
      setSaved(next);
      setForm(next);
      shopify.toast.show(t("saved", "Upsell settings saved"));
    } catch (_e) {
      setError(t("save_error", "Could not save upsell settings."));
    } finally {
      setSaving(false);
    }
  }, [form]);

  const pickProducts = async () => {
    const selected = await shopify.resourcePicker({
      type: "product",
      multiple: true,
      action: "select",
      selectionIds: form.products.map((p) => ({
        id: productGid(p.id),
        ...(p.allSelected ? {} : { variants: p.variants.map((v) => ({ id: variantGid(v.id) })) }),
      })),
    });
    if (!selected) return;
    const existing = Object.fromEntries(form.products.map((p) => [p.id, p]));
    const picked = selected.map(pickerProductRow).map((row) => ({ ...existing[row.id], ...row }));
    const order = form.products.map((p) => p.id);
    picked.sort((a, b) => {
      const ia = order.indexOf(a.id);
      const ib = order.indexOf(b.id);
      return (ia === -1 ? Infinity : ia) - (ib === -1 ? Infinity : ib);
    });
    update({ products: picked });
  };

  const editProduct = async (index) => {
    const row = form.products[index];
    const selected = await shopify.resourcePicker({
      type: "product",
      multiple: false,
      action: "select",
      selectionIds: [{ id: productGid(row.id), variants: row.variants.map((v) => ({ id: variantGid(v.id) })) }],
    });
    if (!selected?.length) return;
    const products = [...form.products];
    products[index] = { autoAdd: row.autoAdd, ...pickerProductRow(selected[0]) };
    update({ products: products.filter((p, i) => i === index || p.id !== products[index].id) });
  };

  const removeVariant = (index, variantId) => {
    const row = form.products[index];
    const variants = row.variants.filter((v) => v.id !== variantId);
    const products = [...form.products];
    if (variants.length === 0) products.splice(index, 1);
    else products[index] = { ...row, variants, allSelected: false };
    update({ products });
  };

  const pickCollections = async () => {
    const selected = await shopify.resourcePicker({
      type: "collection",
      multiple: true,
      action: "select",
      selectionIds: form.collections.map((c) => ({ id: collectionGid(c.id) })),
    });
    if (!selected) return;
    const existing = Object.fromEntries(form.collections.map((c) => [c.id, c]));
    const order = form.collections.map((c) => c.id);
    const picked = selected.map(pickerCollectionRow).map((row) => ({ ...existing[row.id], ...row, productsCount: row.productsCount ?? existing[row.id]?.productsCount }));
    picked.sort((a, b) => {
      const ia = order.indexOf(a.id);
      const ib = order.indexOf(b.id);
      return (ia === -1 ? Infinity : ia) - (ib === -1 ? Infinity : ib);
    });
    update({ collections: picked });
  };

  const tabs = [
    { id: "products", content: t("tab_products", "Products (%{count})", { count: form.products.length }) },
    { id: "collections", content: t("tab_collections", "Collections (%{count})", { count: form.collections.length }) },
  ];

  if (loading) {
    return (
      <Page title={t("title", "Upsell")}>
        <InlineStack align="center">
          <Spinner size="large" />
        </InlineStack>
      </Page>
    );
  }

  return (
    <Page title={t("title", "Upsell")}>
      <SaveBar id="upsell-save-bar" open={isDirty}>
        <button variant="primary" onClick={handleSave} loading={saving ? "" : undefined}>
          {I18n.t("admin.save", { defaultValue: "Save" })}
        </button>
        <button onClick={() => setForm(saved)}>{I18n.t("admin.discard", { defaultValue: "Discard" })}</button>
      </SaveBar>

      <Layout>
        {error && (
          <Layout.Section>
            <Banner tone="critical" onDismiss={() => setError("")}>
              {error}
            </Banner>
          </Layout.Section>
        )}

        <Layout.Section>
          <FeatureCallout
            illustration="widget"
            title={t("title", "Upsell")}
            description={t("enable_help", "Shows a “items you may like” slider in the checkout widget.")}
            showChat
            badge={
              form.enabled ? (
                <Badge tone="success" progress="complete">
                  {I18n.t("pre_order.enabled")}
                </Badge>
              ) : (
                <Badge tone="attention" progress="incomplete">
                  {I18n.t("pre_order.inactive")}
                </Badge>
              )
            }
          />
        </Layout.Section>

        <Layout.Section>
          <FreeGiftCard />
        </Layout.Section>

        <Layout.Section>
          <SectionCard>
            <SettingRow
              title={t("activate", "Activate upsell")}
              description={t("activate_help", "Turn this on to show items you may like in the checkout widget. Your other settings are saved either way.")}
              control={
                <Checkbox
                  label={t("activate", "Activate upsell")}
                  labelHidden
                  checked={form.enabled}
                  onChange={(enabled) => update({ enabled })}
                />
              }
            />
          </SectionCard>
        </Layout.Section>

        <Layout.Section>
          <SectionCard>
            <SettingRow
              title={t("max_items", "Max products to show")}
              description={t("max_items_help", "Products already in the cart are skipped.")}
              control={
                <Select
                  label={t("max_items", "Max products to show")}
                  labelHidden
                  options={[3, 5, 7, 8, 9, 10].map((n) => ({ label: String(n), value: String(n) }))}
                  value={String(form.maxItems)}
                  onChange={(value) => update({ maxItems: Number(value) })}
                />
              }
            />
          </SectionCard>
        </Layout.Section>

        <Layout.Section>
          <SectionCard>
            <SettingRow
              title={t("show_quantity_selector", "Show quantity selector")}
              description={t("show_quantity_selector_help", "Lets customers pick a quantity next to the Add button before adding an upsell product.")}
              control={
                <Checkbox
                  label={t("show_quantity_selector", "Show quantity selector")}
                  labelHidden
                  checked={form.showQuantitySelector}
                  onChange={(showQuantitySelector) => update({ showQuantitySelector })}
                />
              }
            />
          </SectionCard>
        </Layout.Section>

        <Layout.Section>
          <SectionCard>
            <SettingRow
              title={t("vertical_layout", "Show products vertically")}
              description={t("vertical_layout_help", "Stacks upsell products in a vertical list instead of a horizontal slider.")}
              control={
                <Checkbox
                  label={t("vertical_layout", "Show products vertically")}
                  labelHidden
                  checked={form.verticalLayout}
                  onChange={(verticalLayout) => update({ verticalLayout })}
                />
              }
            />
          </SectionCard>
        </Layout.Section>

        <Layout.Section>
          <Card padding="0">
            <Tabs tabs={tabs} selected={tab} onSelect={setTab}>
              <Box padding="400">
                {tab === 0 ? (
                  <BlockStack gap="300">
                    <InlineStack align="space-between" blockAlign="center">
                      <Text as="p" tone="subdued">
                        {t("products_help", "Shown in this order. Auto add puts the product in the cart once, qty 1.")}
                      </Text>
                      <Button onClick={pickProducts}>{t("add_products", "Add products")}</Button>
                    </InlineStack>
                    {form.products.length > 0 && (
                      <SortableList
                        items={form.products}
                        header={<ProductTableHeader />}
                        getKey={(p) => p.id}
                        onReorder={(from, to) => update({ products: moveItem(form.products, from, to) })}
                        renderItem={(row, index) => (
                          <ProductRow
                            row={row}
                            onEdit={() => editProduct(index)}
                            onRemove={() => update({ products: form.products.filter((_, i) => i !== index) })}
                            onRemoveVariant={(variantId) => removeVariant(index, variantId)}
                            onAutoAddChange={(autoAdd) =>
                              update({ products: form.products.map((p, i) => (i === index ? { ...p, autoAdd } : p)) })
                            }
                          />
                        )}
                      />
                    )}
                  </BlockStack>
                ) : (
                  <BlockStack gap="300">
                    <InlineStack align="space-between" blockAlign="center">
                      <Text as="p" tone="subdued">
                        {t("collections_help", "Products from these collections are shown in collection order.")}
                      </Text>
                      <Button onClick={pickCollections}>{t("add_collections", "Add collections")}</Button>
                    </InlineStack>
                    {form.collections.length > 0 && (
                      <SortableList
                        items={form.collections}
                        getKey={(c) => c.id}
                        onReorder={(from, to) => update({ collections: moveItem(form.collections, from, to) })}
                        renderItem={(collection, index) => (
                          <InlineStack align="space-between" blockAlign="center" wrap={false}>
                            <InlineStack gap="300" blockAlign="center" wrap={false}>
                              <Thumbnail source={collection.image || ImageMajor} alt={collection.title} size="small" />
                              <BlockStack gap="050">
                                <Text as="span" fontWeight="semibold">
                                  {collection.title}
                                </Text>
                                {collection.productsCount != null && (
                                  <Text as="span" tone="subdued" variant="bodySm">
                                    {t("products_count", "%{count} products", { count: collection.productsCount })}
                                  </Text>
                                )}
                              </BlockStack>
                            </InlineStack>
                            <Button
                              icon={DeleteMinor}
                              variant="tertiary"
                              tone="critical"
                              accessibilityLabel={t("remove", "Remove")}
                              onClick={() => update({ collections: form.collections.filter((_, i) => i !== index) })}
                            />
                          </InlineStack>
                        )}
                      />
                    )}
                  </BlockStack>
                )}
              </Box>
            </Tabs>
          </Card>
        </Layout.Section>

      </Layout>
    </Page>
  );
}
