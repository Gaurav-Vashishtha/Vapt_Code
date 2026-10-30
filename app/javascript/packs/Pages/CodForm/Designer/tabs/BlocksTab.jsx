import React, { useState } from "react";
import { ActionList, Badge, BlockStack, Button, Card, Checkbox, InlineStack, Popover, Text } from "@shopify/polaris";
import { EditMinor, DeleteMinor } from "@shopify/polaris-icons";
import { useGate } from "../../components/Gate";
import { FEATURES } from "../../constants";
import { CONTENT_BLOCK_TYPES } from "../../defaults";
import { moveItem, randomKey } from "../../utils";
import { t } from "../../i18n";
import SortableList from "../SortableList";
import ContentBlockModal from "../ContentBlockModal";
import { blockName } from "../fieldLabels";

const ALWAYS_ON = ["contact", "address", "submit"];

const newBlock = (type) => {
  const id = `${type}_${randomKey(6)}`;
  switch (type) {
    case "rich_text":
      return { id, type, enabled: true, settings: { html: "" } };
    case "image":
      return { id, type, enabled: true, settings: { url: "", alt: "", link: "" } };
    case "trust_badges":
      return { id, type, enabled: true, settings: { items: [{ icon: "shield", text: "" }] } };
    case "countdown":
      return { id, type, enabled: true, settings: { minutes: 10, text_key: `block_${id}_text` } };
    default:
      return { id, type, enabled: true, settings: { offer_id: null } };
  }
};

/* The submit block is always the last enabled block (C.2). */
const submitLast = (blocks) => {
  const submit = blocks.filter((block) => block.type === "submit");
  return [...blocks.filter((block) => block.type !== "submit"), ...submit];
};

/** Blocks: order, on / off, per-block settings, content blocks (FRM-2, FRM-12, FRM-14, FRM-23). */
const BlocksTab = ({ config, setConfig, locale }) => {
  const [menuOpen, setMenuOpen] = useState(false);
  const [editing, setEditing] = useState(null);
  const thresholdGate = useGate(FEATURES.THRESHOLD_OFFERS);
  const blocks = config.blocks || [];

  const writeBlocks = (next) => setConfig((current) => ({ ...current, blocks: submitLast(next) }));
  const patch = (id, changes) => writeBlocks(blocks.map((block) => (block.id === id ? { ...block, ...changes } : block)));
  const setSetting = (id, key, value) =>
    writeBlocks(blocks.map((block) => (block.id === id ? { ...block, settings: { ...(block.settings || {}), [key]: value } } : block)));

  const add = (type) => {
    setMenuOpen(false);
    const block = newBlock(type);
    writeBlocks([...blocks, block]);
    setEditing(block);
  };

  const remove = (id) =>
    setConfig((current) => {
      const texts = {};
      Object.keys(current.texts || {}).forEach((code) => {
        const set = { ...current.texts[code] };
        delete set[`block_${id}_text`];
        if (Object.keys(set).length) texts[code] = set;
      });
      return { ...current, texts, blocks: (current.blocks || []).filter((block) => block.id !== id) };
    });

  const saveBlock = (block, text) => {
    setConfig((current) => {
      let texts = current.texts || {};
      if (block.type === "countdown") {
        const key = `block_${block.id}_text`;
        const set = { ...(texts[locale] || {}) };
        if (text) set[key] = text;
        else delete set[key];
        // Kept even when empty: an added language stays in the list (see setTextOverride).
        texts = { ...texts, [locale]: set };
      }
      return {
        ...current,
        texts,
        blocks: submitLast((current.blocks || []).map((item) => (item.id === block.id ? block : item))),
      };
    });
    setEditing(null);
  };

  const renderBlock = (block) => {
    const content = CONTENT_BLOCK_TYPES.includes(block.type);
    const locked = ALWAYS_ON.includes(block.id);
    const settings = block.settings || {};
    return (
      <BlockStack gap="200">
        <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
          <InlineStack gap="200" blockAlign="center">
            <Text as="span" variant="bodyMd" fontWeight="semibold">
              {blockName(block)}
            </Text>
            {!block.enabled && <Badge>{t("common.disabled", "Off")}</Badge>}
            {block.type === "submit" && <Badge tone="info">{t("designer.block_always_last", "Always last")}</Badge>}
          </InlineStack>
          <InlineStack gap="200" blockAlign="center" wrap={false}>
            <Checkbox
              label={t("designer.field_show_short", "Show")}
              checked={!!block.enabled}
              disabled={locked}
              onChange={(value) => patch(block.id, { enabled: value })}
            />
            {content && (
              <>
                <Button icon={EditMinor} onClick={() => setEditing(block)} accessibilityLabel={t("common.edit", "Edit")} />
                <Button
                  icon={DeleteMinor}
                  tone="critical"
                  onClick={() => remove(block.id)}
                  accessibilityLabel={t("common.delete", "Delete")}
                />
              </>
            )}
          </InlineStack>
        </InlineStack>
        {block.enabled && block.type === "order_summary" && (
          <InlineStack gap="400" wrap>
            <Checkbox
              label={t("designer.summary_show_image", "Product image")}
              checked={settings.show_image !== false}
              onChange={(value) => setSetting(block.id, "show_image", value)}
            />
            <Checkbox
              label={t("designer.summary_show_compare_at", "Compare-at price")}
              checked={settings.show_compare_at !== false}
              onChange={(value) => setSetting(block.id, "show_compare_at", value)}
            />
            <Checkbox
              label={t("designer.summary_show_quantity", "Quantity selector")}
              checked={settings.show_quantity !== false}
              onChange={(value) => setSetting(block.id, "show_quantity", value)}
            />
          </InlineStack>
        )}
        {block.enabled && block.type === "totals" && (
          <Checkbox
            label={t("designer.totals_show_tax", "Show the tax line")}
            checked={!!settings.show_tax_line}
            onChange={(value) => setSetting(block.id, "show_tax_line", value)}
          />
        )}
        {block.type === "submit" && (
          <Checkbox
            label={t("designer.submit_show_total", "Show the total in the button")}
            checked={settings.show_total_in_button !== false}
            onChange={(value) => setSetting(block.id, "show_total_in_button", value)}
          />
        )}
        {block.enabled && block.type === "discount" && (
          <Text as="p" variant="bodySm" tone="subdued">
            {t("designer.discount_block_note", "Also turn on discount codes in Setup, under More options.")}
          </Text>
        )}
        {block.type === "quantity_offer" && (
          <Text as="p" variant="bodySm" tone="subdued">
            {t("designer.offer_block_note", "Shown only for products that have an active quantity offer.")}
          </Text>
        )}
        {block.type === "bumps" && (
          <Text as="p" variant="bodySm" tone="subdued">
            {t("designer.bumps_block_note", "Shown only when an order bump matches the cart. Up to 3 bumps are shown.")}
          </Text>
        )}
      </BlockStack>
    );
  };

  const addActions = CONTENT_BLOCK_TYPES.map((type) => ({
    content: blockName({ type }),
    disabled: type === "threshold_bar" && !thresholdGate.allowed,
    helpText:
      type === "threshold_bar" && !thresholdGate.allowed
        ? t("designer.block_needs_plan", "Needs a higher plan")
        : undefined,
    onAction: () => add(type),
  }));

  return (
    <BlockStack gap="400">
      <Card>
        <BlockStack gap="200">
          <InlineStack align="space-between" blockAlign="center">
            <Text as="h3" variant="headingSm">
              {t("designer.blocks_title", "Form blocks")}
            </Text>
            <Popover
              active={menuOpen}
              onClose={() => setMenuOpen(false)}
              activator={
                <Button disclosure onClick={() => setMenuOpen((value) => !value)}>
                  {t("designer.add_block", "Add block")}
                </Button>
              }
            >
              <ActionList items={addActions} />
            </Popover>
          </InlineStack>
          <SortableList
            items={blocks}
            getKey={(block) => block.id}
            isLocked={(block) => block.type === "submit"}
            onReorder={(from, to) => writeBlocks(moveItem(blocks, from, to))}
            renderItem={renderBlock}
          />
        </BlockStack>
      </Card>
      <ContentBlockModal
        open={!!editing}
        block={editing}
        text={editing ? ((config.texts || {})[locale] || {})[`block_${editing.id}_text`] : ""}
        onClose={() => setEditing(null)}
        onSave={saveBlock}
      />
    </BlockStack>
  );
};

export default BlocksTab;
