import React, { useEffect, useState } from "react";
import { Modal, BlockStack, Button, InlineStack, Select, TextField, Text, Banner } from "@shopify/polaris";
import { DeleteMinor } from "@shopify/polaris-icons";
import { codFormApi } from "../api";
import { LIMITS } from "../constants";
import { clone, toInt } from "../utils";
import { t } from "../i18n";
import { blockName } from "./fieldLabels";

const BADGE_ICONS = ["shield", "truck", "cash", "return", "lock", "star"];

const badgeIconName = (icon) => {
  switch (icon) {
    case "truck":
      return t("designer.badge_icon_truck", "Truck");
    case "cash":
      return t("designer.badge_icon_cash", "Cash");
    case "return":
      return t("designer.badge_icon_return", "Returns");
    case "lock":
      return t("designer.badge_icon_lock", "Lock");
    case "star":
      return t("designer.badge_icon_star", "Star");
    default:
      return t("designer.badge_icon_shield", "Shield");
  }
};

/** Settings of a content block (FRM-14, FRM-23, OFF-11 progress bar). */
const ContentBlockModal = ({ open, block, text, onClose, onSave }) => {
  const [draft, setDraft] = useState(null);
  const [blockText, setBlockText] = useState("");
  const [thresholds, setThresholds] = useState(null);

  useEffect(() => {
    if (!open || !block) return;
    setDraft(clone(block));
    setBlockText(text || "");
  }, [open, block, text]);

  useEffect(() => {
    if (!open || !block || block.type !== "threshold_bar" || thresholds) return;
    codFormApi.offers
      .index("threshold")
      .then((response) => setThresholds((response && response.items) || []))
      .catch(() => setThresholds([]));
  }, [open, block, thresholds]);

  if (!draft) return null;
  const settings = draft.settings || {};
  const set = (key, value) => setDraft((current) => ({ ...current, settings: { ...(current.settings || {}), [key]: value } }));
  const items = settings.items || [];
  const httpsError = (url) =>
    url && !/^https:\/\//i.test(url) ? t("designer.https_required", "Use a link that starts with https://") : undefined;

  const invalid =
    (draft.type === "image" && (!settings.url || !!httpsError(settings.url) || !!httpsError(settings.link))) ||
    (draft.type === "trust_badges" && items.filter((item) => item.text).length === 0) ||
    (draft.type === "countdown" && !(Number(settings.minutes) > 0)) ||
    (draft.type === "threshold_bar" && !settings.offer_id);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={blockName(draft)}
      primaryAction={{ content: t("common.done", "Done"), onAction: () => onSave(draft, blockText), disabled: invalid }}
      secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="400">
          {draft.type === "rich_text" && (
            <TextField
              label={t("designer.rich_text_html", "Text")}
              value={settings.html || ""}
              onChange={(value) => set("html", value)}
              multiline={5}
              helpText={t("designer.rich_text_help", "Simple HTML is allowed: b, i, u, strong, em, a (https links), br, p, ul, ol, li, span. Anything else is removed when you save.")}
              autoComplete="off"
            />
          )}

          {draft.type === "image" && (
            <>
              <TextField
                label={t("designer.image_url", "Image or GIF URL")}
                value={settings.url || ""}
                onChange={(value) => set("url", value.trim())}
                error={httpsError(settings.url)}
                placeholder="https://cdn.shopify.com/…"
                autoComplete="off"
              />
              <TextField
                label={t("designer.image_alt", "Description for screen readers")}
                value={settings.alt || ""}
                onChange={(value) => set("alt", value)}
                autoComplete="off"
              />
              <TextField
                label={t("designer.image_link", "Link (optional)")}
                value={settings.link || ""}
                onChange={(value) => set("link", value.trim())}
                error={httpsError(settings.link)}
                autoComplete="off"
              />
            </>
          )}

          {draft.type === "trust_badges" && (
            <>
              {items.map((item, index) => (
                <InlineStack key={index} gap="200" blockAlign="end" wrap={false}>
                  <Select
                    label={t("designer.badge_icon", "Icon")}
                    options={BADGE_ICONS.map((icon) => ({ value: icon, label: badgeIconName(icon) }))}
                    value={item.icon || "shield"}
                    onChange={(value) => set("items", items.map((entry, i) => (i === index ? { ...entry, icon: value } : entry)))}
                  />
                  <div style={{ flex: 1 }}>
                    <TextField
                      label={t("designer.badge_text", "Text")}
                      value={item.text || ""}
                      onChange={(value) => set("items", items.map((entry, i) => (i === index ? { ...entry, text: value } : entry)))}
                      maxLength={60}
                      autoComplete="off"
                    />
                  </div>
                  <Button
                    icon={DeleteMinor}
                    accessibilityLabel={t("common.delete", "Delete")}
                    onClick={() => set("items", items.filter((_, i) => i !== index))}
                  />
                </InlineStack>
              ))}
              <InlineStack>
                <Button onClick={() => set("items", [...items, { icon: "shield", text: "" }])} disabled={items.length >= 6}>
                  {t("designer.add_badge", "Add badge")}
                </Button>
              </InlineStack>
            </>
          )}

          {draft.type === "countdown" && (
            <>
              <TextField
                label={t("designer.countdown_minutes", "Minutes")}
                type="number"
                min={1}
                max={1440}
                value={settings.minutes == null ? "" : String(settings.minutes)}
                onChange={(value) => set("minutes", toInt(value))}
                autoComplete="off"
              />
              <TextField
                label={t("designer.countdown_text", "Text before the timer")}
                value={blockText}
                onChange={setBlockText}
                maxLength={LIMITS.TEXT_MAX_CHARS}
                placeholder={t("designer.countdown_text_placeholder", "Offer ends in")}
                autoComplete="off"
              />
            </>
          )}

          {draft.type === "threshold_bar" &&
            (thresholds === null ? (
              <Text as="p" tone="subdued">
                {t("common.loading", "Loading…")}
              </Text>
            ) : thresholds.length === 0 ? (
              <Banner tone="info">
                <p>{t("designer.threshold_none", "Create a free shipping or free gift offer in Offers first, then pick it here.")}</p>
              </Banner>
            ) : (
              <Select
                label={t("designer.threshold_offer", "Threshold offer")}
                options={[
                  { value: "", label: t("common.select", "Select") },
                  ...thresholds.map((offer) => ({ value: String(offer.id), label: offer.name || `#${offer.id}` })),
                ]}
                value={settings.offer_id ? String(settings.offer_id) : ""}
                onChange={(value) => set("offer_id", value ? toInt(value) : null)}
              />
            ))}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

export default ContentBlockModal;
