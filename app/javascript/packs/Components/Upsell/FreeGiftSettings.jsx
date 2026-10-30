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
  ChoiceList,
  Divider,
  InlineGrid,
  InlineStack,
  Layout,
  Page,
  Popover,
  Select,
  Spinner,
  Tag,
  Text,
  TextField,
  Thumbnail,
} from "@shopify/polaris";
import { HorizontalDotsMinor, ImageMajor } from "@shopify/polaris-icons";
import { SaveBar } from "@shopify/app-bridge-react";
import styled from "styled-components";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import SortableList from "../../Pages/CodForm/Designer/SortableList";
import { SectionCard, SettingRow } from "../SettingsPrimitives";
import { navigateTo } from "../../../utils/navigate";

const t = (key, fallback, opts = {}) => I18n.t(`free_gift.${key}`, { defaultValue: fallback, ...opts });

const numericId = (gid) => Number(String(gid).split("/").pop());
const productGid = (id) => `gid://shopify/Product/${id}`;
const variantGid = (id) => `gid://shopify/ProductVariant/${id}`;
const collectionGid = (id) => `gid://shopify/Collection/${id}`;

const TRIGGERS = [
  { value: "cart_range", label: t("trigger_cart_range", "Cart value") },
  { value: "cart_items", label: t("trigger_cart_items", "Number of items in cart") },
  { value: "product", label: t("trigger_product", "Specific products") },
  { value: "collection", label: t("trigger_collection", "Products from collections") },
];

const EMPTY_FORM = {
  enabled: false,
  stacking: false,
  removeWhenIneligible: true,
  showProgress: true,
  progressMessage: "Add {remaining} more to get {gift} free",
  unlockedMessage: "You've unlocked a free {gift}!",
  badgeLabel: "Free",
  rules: [],
};

const newRule = () => ({
  id: `fg_${Math.random().toString(36).slice(2, 12)}`,
  title: "",
  enabled: true,
  trigger: "cart_range",
  minAmount: "",
  maxAmount: "",
  minItems: 2,
  productIds: [],
  match: "any",
  collectionIds: [],
  minQuantity: 1,
  giftProductId: null,
  giftVariantId: null,
  giftQuantity: 1,
  gift: {},
});

const moveItem = (list, from, to) => {
  const next = [...list];
  const [item] = next.splice(from, 1);
  next.splice(to, 0, item);
  return next;
};

const toForm = (data) => {
  const config = data?.config;
  if (!config) return EMPTY_FORM;
  return {
    ...EMPTY_FORM,
    ...config,
    rules: (config.rules || []).map((rule) => ({
      ...newRule(),
      ...rule,
      minAmount: rule.minAmount ?? "",
      maxAmount: rule.maxAmount ?? "",
      gift: rule.gift || {},
    })),
  };
};

const toConfig = (form) => ({
  enabled: form.enabled,
  stacking: form.stacking,
  removeWhenIneligible: form.removeWhenIneligible,
  showProgress: form.showProgress,
  progressMessage: form.progressMessage,
  unlockedMessage: form.unlockedMessage,
  badgeLabel: form.badgeLabel,
  rules: form.rules.map((rule) => ({
    id: rule.id,
    title: rule.title,
    enabled: rule.enabled,
    trigger: rule.trigger,
    minAmount: rule.minAmount === "" ? null : rule.minAmount,
    maxAmount: rule.maxAmount === "" ? null : rule.maxAmount,
    minItems: rule.minItems,
    productIds: rule.productIds,
    match: rule.match,
    collectionIds: rule.collectionIds,
    minQuantity: rule.minQuantity,
    giftProductId: rule.giftProductId,
    giftVariantId: rule.giftVariantId,
    giftQuantity: rule.giftQuantity,
    gift: rule.gift,
  })),
});

const ruleSummary = (rule, lookups) => {
  switch (rule.trigger) {
    case "cart_range":
      return rule.maxAmount !== "" && rule.maxAmount != null
        ? t("summary_range", "Cart value %{min} – %{max}", { min: rule.minAmount, max: rule.maxAmount })
        : t("summary_min", "Cart value %{min} or more", { min: rule.minAmount || 0 });
    case "cart_items":
      return t("summary_items", "%{count}+ items in cart", { count: rule.minItems });
    case "product": {
      const names = rule.productIds.map((id) => lookups.products[id]?.title || `#${id}`);
      return t("summary_products", "%{match} of: %{names}", {
        match: rule.match === "all" ? t("all", "All") : t("any", "Any"),
        names: names.join(", "),
      });
    }
    case "collection": {
      const names = rule.collectionIds.map((id) => lookups.collections[id]?.title || `#${id}`);
      return t("summary_collections", "%{count}+ items from %{names}", { count: rule.minQuantity, names: names.join(", ") });
    }
    default:
      return "";
  }
};

const RuleGrid = styled.div`
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(0, 1.6fr) 56px 88px 36px;
  align-items: center;
  gap: 12px;

  @media (max-width: 640px) {
    grid-template-columns: minmax(0, 1fr) 36px;
    & > :nth-child(2),
    & > :nth-child(3),
    & > :nth-child(4) {
      display: none;
    }
  }
`;

function RulesHeader() {
  const head = (text) => (
    <Text as="span" variant="bodySm" fontWeight="semibold" tone="subdued">
      {text}
    </Text>
  );
  return (
    <RuleGrid>
      {head(t("col_gift", "Gift"))}
      {head(t("col_condition", "Condition"))}
      {head(t("col_qty", "Qty"))}
      {head(t("col_status", "Status"))}
      <span />
    </RuleGrid>
  );
}

function RuleRow({ rule, index, lookups, giftStatus, onEdit, onToggle, onRemove }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const status = giftStatus[rule.giftVariantId];
  const unavailable = status && (!status.available || !status.active);
  return (
    <RuleGrid>
      <InlineStack gap="300" blockAlign="center" wrap={false}>
        <Thumbnail source={rule.gift?.image || ImageMajor} alt={rule.gift?.title || ""} size="small" />
        <BlockStack gap="050">
          <Button variant="plain" textAlign="left" onClick={onEdit}>
            {rule.title || rule.gift?.title || t("rule_n", "Rule %{n}", { n: index + 1 })}
          </Button>
          <Text as="span" variant="bodySm" tone={unavailable ? "critical" : "subdued"}>
            {unavailable
              ? t("gift_unavailable", "Gift is out of stock or not active")
              : [rule.gift?.title, rule.gift?.variantTitle].filter(Boolean).join(" · ")}
          </Text>
        </BlockStack>
      </InlineStack>
      <Text as="span" variant="bodySm" truncate>
        {ruleSummary(rule, lookups)}
      </Text>
      <Text as="span" variant="bodySm">
        {rule.giftQuantity}
      </Text>
      <div>
        <Badge tone={rule.enabled ? "success" : undefined}>{rule.enabled ? t("active", "Active") : t("paused", "Paused")}</Badge>
      </div>
      <Popover
        active={menuOpen}
        onClose={() => setMenuOpen(false)}
        activator={
          <Button icon={HorizontalDotsMinor} variant="tertiary" accessibilityLabel={t("actions", "Actions")} onClick={() => setMenuOpen((v) => !v)} />
        }
      >
        <ActionList
          actionRole="menuitem"
          items={[
            { content: t("edit", "Edit"), onAction: () => { setMenuOpen(false); onEdit(); } },
            { content: rule.enabled ? t("pause", "Pause") : t("activate_rule", "Activate"), onAction: () => { setMenuOpen(false); onToggle(); } },
            { content: t("remove", "Remove"), destructive: true, onAction: () => { setMenuOpen(false); onRemove(); } },
          ]}
        />
      </Popover>
    </RuleGrid>
  );
}

function RuleEditor({ initial, lookups, onLookups, onDone, onCancel }) {
  const [rule, setRule] = useState(initial);
  const [error, setError] = useState("");
  const patch = (next) => setRule((r) => ({ ...r, ...next }));

  const pickGift = async () => {
    const selected = await shopify.resourcePicker({
      type: "product",
      multiple: false,
      action: "select",
      filter: { variants: true, draft: false, archived: false },
      selectionIds: rule.giftProductId
        ? [{ id: productGid(rule.giftProductId), variants: rule.giftVariantId ? [{ id: variantGid(rule.giftVariantId) }] : [] }]
        : [],
    });
    const product = selected?.[0];
    const variant = product?.variants?.[0];
    if (!product || !variant) return;
    patch({
      giftProductId: numericId(product.id),
      giftVariantId: numericId(variant.id),
      gift: {
        title: product.title,
        variantTitle: variant.title === "Default Title" ? "" : variant.title,
        image: variant.image?.originalSrc || product.images?.[0]?.originalSrc || product.images?.[0]?.url || null,
        price: variant.price ? Number(variant.price) : null,
      },
    });
  };

  const pickProducts = async () => {
    const selected = await shopify.resourcePicker({
      type: "product",
      multiple: true,
      action: "select",
      filter: { variants: false },
      selectionIds: rule.productIds.map((id) => ({ id: productGid(id) })),
    });
    if (!selected) return;
    const rows = selected.map((p) => ({ id: numericId(p.id), title: p.title, image: p.images?.[0]?.originalSrc || null }));
    onLookups({ products: rows });
    patch({ productIds: rows.map((p) => p.id) });
  };

  const pickCollections = async () => {
    const selected = await shopify.resourcePicker({
      type: "collection",
      multiple: true,
      action: "select",
      selectionIds: rule.collectionIds.map((id) => ({ id: collectionGid(id) })),
    });
    if (!selected) return;
    const rows = selected.map((c) => ({ id: numericId(c.id), title: c.title, image: c.image?.originalSrc || null }));
    onLookups({ collections: rows });
    patch({ collectionIds: rows.map((c) => c.id) });
  };

  const done = () => {
    if (!rule.giftVariantId) return setError(t("err_gift", "Choose the gift product."));
    if (rule.trigger === "cart_range") {
      if (rule.minAmount === "" || Number(rule.minAmount) < 0) return setError(t("err_min", "Enter a minimum cart value."));
      if (rule.maxAmount !== "" && Number(rule.maxAmount) <= Number(rule.minAmount)) {
        return setError(t("err_max", "Maximum must be greater than minimum."));
      }
    }
    if (rule.trigger === "product" && rule.productIds.length === 0) return setError(t("err_products", "Select at least one product."));
    if (rule.trigger === "collection" && rule.collectionIds.length === 0) return setError(t("err_collections", "Select at least one collection."));
    onDone(rule);
  };

  return (
    <Card>
      <BlockStack gap="400">
        <Text as="h3" variant="headingMd">
          {initial.giftVariantId ? t("edit_rule", "Edit rule") : t("new_rule", "New free gift rule")}
        </Text>
        {error && (
          <Banner tone="critical" onDismiss={() => setError("")}>
            {error}
          </Banner>
        )}
        <TextField
          label={t("rule_title", "Rule name")}
          helpText={t("rule_title_help", "Only you see this. Used in reports.")}
          value={rule.title}
          onChange={(title) => patch({ title })}
          maxLength={80}
          autoComplete="off"
        />

        <Divider />
        <Text as="h4" variant="headingSm">
          {t("when", "When")}
        </Text>
        <Select label={t("trigger", "Customer qualifies by")} options={TRIGGERS} value={rule.trigger} onChange={(trigger) => patch({ trigger })} />

        {rule.trigger === "cart_range" && (
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="300">
            <TextField
              label={t("min_amount", "Cart value from")}
              type="number"
              min={0}
              value={String(rule.minAmount ?? "")}
              onChange={(minAmount) => patch({ minAmount })}
              autoComplete="off"
            />
            <TextField
              label={t("max_amount", "Up to (optional)")}
              helpText={t("max_amount_help", "Leave empty for no upper limit. Use ranges to give bigger gifts for bigger carts.")}
              type="number"
              min={0}
              value={String(rule.maxAmount ?? "")}
              onChange={(maxAmount) => patch({ maxAmount })}
              autoComplete="off"
            />
          </InlineGrid>
        )}

        {rule.trigger === "cart_items" && (
          <TextField
            label={t("min_items", "Minimum items in cart")}
            type="number"
            min={1}
            value={String(rule.minItems)}
            onChange={(v) => patch({ minItems: Math.max(1, Number(v) || 1) })}
            autoComplete="off"
          />
        )}

        {rule.trigger === "product" && (
          <BlockStack gap="300">
            <InlineStack gap="200" blockAlign="center">
              <Button onClick={pickProducts}>{t("select_products", "Select products")}</Button>
              <Text as="span" tone="subdued">
                {t("selected_count", "%{count} selected", { count: rule.productIds.length })}
              </Text>
            </InlineStack>
            <InlineStack gap="100">
              {rule.productIds.map((id) => (
                <Tag key={id} onRemove={() => patch({ productIds: rule.productIds.filter((p) => p !== id) })}>
                  {lookups.products[id]?.title || `#${id}`}
                </Tag>
              ))}
            </InlineStack>
            <ChoiceList
              title={t("match", "Cart must contain")}
              choices={[
                { label: t("match_any", "Any of these products"), value: "any" },
                { label: t("match_all", "All of these products"), value: "all" },
              ]}
              selected={[rule.match]}
              onChange={([match]) => patch({ match })}
            />
          </BlockStack>
        )}

        {rule.trigger === "collection" && (
          <BlockStack gap="300">
            <InlineStack gap="200" blockAlign="center">
              <Button onClick={pickCollections}>{t("select_collections", "Select collections")}</Button>
              <Text as="span" tone="subdued">
                {t("selected_count", "%{count} selected", { count: rule.collectionIds.length })}
              </Text>
            </InlineStack>
            <InlineStack gap="100">
              {rule.collectionIds.map((id) => (
                <Tag key={id} onRemove={() => patch({ collectionIds: rule.collectionIds.filter((c) => c !== id) })}>
                  {lookups.collections[id]?.title || `#${id}`}
                </Tag>
              ))}
            </InlineStack>
            <TextField
              label={t("min_quantity", "Minimum items from these collections")}
              type="number"
              min={1}
              value={String(rule.minQuantity)}
              onChange={(v) => patch({ minQuantity: Math.max(1, Number(v) || 1) })}
              autoComplete="off"
            />
          </BlockStack>
        )}

        <Divider />
        <Text as="h4" variant="headingSm">
          {t("gift", "Free gift")}
        </Text>
        <InlineStack gap="300" blockAlign="center" wrap={false}>
          <Thumbnail source={rule.gift?.image || ImageMajor} alt={rule.gift?.title || ""} size="small" />
          <Box minWidth="0" width="100%">
            <BlockStack gap="050">
              <Text as="span" fontWeight="semibold">
                {rule.gift?.title || t("no_gift", "No gift selected")}
              </Text>
              {rule.gift?.variantTitle && (
                <Text as="span" tone="subdued" variant="bodySm">
                  {rule.gift.variantTitle}
                </Text>
              )}
            </BlockStack>
          </Box>
          <Button onClick={pickGift}>{rule.giftVariantId ? t("change_gift", "Change") : t("choose_gift", "Choose gift")}</Button>
        </InlineStack>
        <TextField
          label={t("gift_quantity", "Gift quantity")}
          type="number"
          min={1}
          max={10}
          value={String(rule.giftQuantity)}
          onChange={(v) => patch({ giftQuantity: Math.min(10, Math.max(1, Number(v) || 1)) })}
          autoComplete="off"
        />
        <Checkbox label={t("rule_enabled", "Rule is active")} checked={rule.enabled} onChange={(enabled) => patch({ enabled })} />

        <InlineStack align="end" gap="200">
          <Button onClick={onCancel}>{t("cancel", "Cancel")}</Button>
          <Button variant="primary" onClick={done}>
            {t("done", "Done")}
          </Button>
        </InlineStack>
      </BlockStack>
    </Card>
  );
}

export default function FreeGiftSettings() {
  const [saved, setSaved] = useState(EMPTY_FORM);
  const [form, setForm] = useState(EMPTY_FORM);
  const [lookups, setLookups] = useState({ products: {}, collections: {} });
  const [giftStatus, setGiftStatus] = useState({});
  const [editing, setEditing] = useState(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const applyResponse = (data) => {
    const next = toForm(data);
    setSaved(next);
    setForm(next);
    setGiftStatus(data?.giftStatus || {});
    setLookups((prev) => ({
      products: { ...prev.products, ...Object.fromEntries((data?.products || []).map((p) => [p.id, p])) },
      collections: { ...prev.collections, ...Object.fromEntries((data?.collections || []).map((c) => [c.id, c])) },
    }));
  };

  useEffect(() => {
    Api.get("/free_gift_config")
      .then((res) => applyResponse(res.data))
      .catch(() => setError(t("load_error", "Could not load free gift settings.")))
      .finally(() => setLoading(false));
  }, []);

  const isDirty = useMemo(() => JSON.stringify(toConfig(form)) !== JSON.stringify(toConfig(saved)), [form, saved]);
  const update = (patch) => setForm((f) => ({ ...f, ...patch }));

  const mergeLookups = ({ products = [], collections = [] }) =>
    setLookups((prev) => ({
      products: { ...prev.products, ...Object.fromEntries(products.map((p) => [p.id, p])) },
      collections: { ...prev.collections, ...Object.fromEntries(collections.map((c) => [c.id, c])) },
    }));

  const handleSave = useCallback(async () => {
    setSaving(true);
    setError("");
    try {
      const res = await Api.post("/free_gift_config", { freeGiftConfig: toConfig(form) });
      applyResponse(res.data);
      shopify.toast.show(t("saved", "Free gift settings saved"));
    } catch (e) {
      setError(e?.response?.data?.error || t("save_error", "Could not save free gift settings."));
    } finally {
      setSaving(false);
    }
  }, [form]);

  const saveRule = (rule) => {
    const exists = form.rules.some((r) => r.id === rule.id);
    update({ rules: exists ? form.rules.map((r) => (r.id === rule.id ? rule : r)) : [...form.rules, rule] });
    setEditing(null);
  };

  const backAction = { content: t("back", "Upsell"), onAction: () => navigateTo("/features/upsell") };

  if (loading) {
    return (
      <Page title={t("title", "Free gifts")} backAction={backAction}>
        <InlineStack align="center">
          <Spinner size="large" />
        </InlineStack>
      </Page>
    );
  }

  return (
    <Page
      title={t("title", "Free gifts")}
      subtitle={t("subtitle", "Add a free product to the cart when the customer qualifies.")}
      backAction={backAction}
      titleMetadata={
        form.enabled ? <Badge tone="success">{t("on", "On")}</Badge> : <Badge>{t("off", "Off")}</Badge>
      }
    >
      <SaveBar id="free-gift-save-bar" open={isDirty}>
        <button variant="primary" onClick={handleSave} loading={saving ? "" : undefined}>
          {I18n.t("admin.save", { defaultValue: "Save" })}
        </button>
        <button onClick={() => { setForm(saved); setEditing(null); }}>{I18n.t("admin.discard", { defaultValue: "Discard" })}</button>
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
          <SectionCard>
            <SettingRow
              title={t("activate", "Activate free gifts")}
              description={t("activate_help", "Qualifying customers get the gift added to their cart at no cost.")}
              control={
                <Checkbox label={t("activate", "Activate free gifts")} labelHidden checked={form.enabled} onChange={(enabled) => update({ enabled })} />
              }
            />
          </SectionCard>
        </Layout.Section>

        <Layout.Section>
          {editing ? (
            <RuleEditor
              key={editing.id}
              initial={editing}
              lookups={lookups}
              onLookups={mergeLookups}
              onDone={saveRule}
              onCancel={() => setEditing(null)}
            />
          ) : (
            <Card>
              <BlockStack gap="300">
                <InlineStack align="space-between" blockAlign="center">
                  <BlockStack gap="050">
                    <Text as="h3" variant="headingMd">
                      {t("rules", "Gift rules")}
                    </Text>
                    <Text as="p" tone="subdued" variant="bodySm">
                      {form.stacking
                        ? t("rules_help_stack", "Every matching rule adds its gift. Drag to reorder.")
                        : t("rules_help", "Checked top to bottom. The first matching rule wins. Drag to reorder.")}
                    </Text>
                  </BlockStack>
                  <Button variant="primary" onClick={() => setEditing(newRule())} disabled={form.rules.length >= 20}>
                    {t("add_rule", "Add rule")}
                  </Button>
                </InlineStack>
                {form.rules.length === 0 ? (
                  <Box paddingBlock="600">
                    <BlockStack gap="100" inlineAlign="center">
                      <Text as="p" fontWeight="semibold">
                        {t("empty_heading", "No free gift rules yet")}
                      </Text>
                      <Text as="p" tone="subdued">
                        {t("empty_body", "Reward customers by cart value, number of items, products or collections.")}
                      </Text>
                    </BlockStack>
                  </Box>
                ) : (
                  <SortableList
                    items={form.rules}
                    header={<RulesHeader />}
                    getKey={(r) => r.id}
                    onReorder={(from, to) => update({ rules: moveItem(form.rules, from, to) })}
                    renderItem={(rule, index) => (
                      <RuleRow
                        rule={rule}
                        index={index}
                        lookups={lookups}
                        giftStatus={giftStatus}
                        onEdit={() => setEditing(rule)}
                        onToggle={() => update({ rules: form.rules.map((r) => (r.id === rule.id ? { ...r, enabled: !r.enabled } : r)) })}
                        onRemove={() => update({ rules: form.rules.filter((r) => r.id !== rule.id) })}
                      />
                    )}
                  />
                )}
              </BlockStack>
            </Card>
          )}
        </Layout.Section>

        <Layout.Section>
          <SectionCard title={t("additional", "Additional settings")}>
            <SettingRow
              title={t("stacking", "Give gifts from every matching rule")}
              description={t("stacking_help", "Off: only the first matching rule gives a gift.")}
              control={<Checkbox label={t("stacking", "Stacking")} labelHidden checked={form.stacking} onChange={(stacking) => update({ stacking })} />}
            />
            <SettingRow
              title={t("remove", "Remove gift when cart no longer qualifies")}
              description={t("remove_help", "If the customer removes items and drops below the condition, the gift is taken out.")}
              control={
                <Checkbox
                  label={t("remove", "Remove gift")}
                  labelHidden
                  checked={form.removeWhenIneligible}
                  onChange={(removeWhenIneligible) => update({ removeWhenIneligible })}
                />
              }
            />
            <SettingRow
              title={t("show_progress", "Show progress message")}
              description={t("show_progress_help", "Tells customers how much more to add to unlock the next gift.")}
              control={
                <Checkbox label={t("show_progress", "Show progress")} labelHidden checked={form.showProgress} onChange={(showProgress) => update({ showProgress })} />
              }
            />
            <TextField
              label={t("progress_message", "Progress message")}
              helpText={t("placeholders", "Use {remaining} for the amount left and {gift} for the gift name.")}
              value={form.progressMessage}
              onChange={(progressMessage) => update({ progressMessage })}
              maxLength={120}
              disabled={!form.showProgress}
              autoComplete="off"
            />
            <TextField
              label={t("unlocked_message", "Unlocked message")}
              value={form.unlockedMessage}
              onChange={(unlockedMessage) => update({ unlockedMessage })}
              maxLength={120}
              autoComplete="off"
            />
            <TextField
              label={t("badge_label", "Gift badge label")}
              value={form.badgeLabel}
              onChange={(badgeLabel) => update({ badgeLabel })}
              maxLength={20}
              autoComplete="off"
            />
          </SectionCard>
        </Layout.Section>
      </Layout>
    </Page>
  );
}
