import React, { useCallback, useEffect, useState } from "react";
import { Select, Text, BlockStack } from "@shopify/polaris";
import Api from "../../Services/Api.js";
import I18n from "../../i18n-lang.js";

// Notification keys used by GET /api/whatsapp/languages previews (camelized by the Api client).
export const WA_PREVIEW_EVENTS = {
  orderConfirmation: "orderConfirmation",
  fulfilment: "fulfilment",
  abandonedCart: "abandonedCart",
  abandonedCartDiscount: "abandonedCartDiscount",
  codVerification: "codVerification",
  firstPurchase: "firstPurchase",
};

const t = (key, fallback, opts = {}) => I18n.t(key, { defaultValue: fallback, ...opts });

/** Language options, onboarding suggestion and previews for the shop's WhatsApp notifications. */
export function useWhatsappLanguages() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(() => {
    setLoading(true);
    return Api.get("/api/whatsapp/languages")
      .then((res) => {
        setData(res.data);
        return res.data;
      })
      .catch((err) => {
        console.error("WhatsApp languages failed to load", err);
        setData(null);
        return null;
      })
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return { data, loading, reload: load };
}

/**
 * Save the shop's WhatsApp language. `suggested: true` applies the onboarding country default and is
 * ignored by the server once the merchant has picked a language; otherwise the pick is remembered as
 * the merchant's own choice.
 */
export function saveWhatsappLanguage(language, { suggested = false } = {}) {
  return Api.patch("/api/whatsapp/language", { language, suggested }).then((res) => res.data);
}

/** Preview entry for `event` in `language`, or null for English / not offered. */
export function previewFor(data, language, event) {
  if (!data || !language || language === "en") return null;
  return data.previews?.[language]?.[event] || null;
}

export function isRtl(data, language) {
  return Boolean(data?.options?.find((o) => o.code === language)?.rtl);
}

/**
 * Language dropdown for customer WhatsApp messages. Shown only for shops on COD King's default
 * number; a shop on its own number sends its own templates, so the language is theirs to set there.
 */
export function WhatsappLanguagePicker({ data, value, onChange, disabled }) {
  if (!data || data.ownNumber) return null;
  const options = data.options || [];
  if (options.length <= 1 && (value || "en") === "en") return null;

  const current = options.find((o) => o.code === value) || options[0];
  const selectOptions = options.map((o) => ({
    value: o.code,
    label:
      o.code === "en"
        ? "English"
        : `${o.native} — ${o.name}${o.fullyApproved ? "" : ` (${o.approvedCount}/${o.totalCount})`}`,
  }));
  // Keep a saved language selectable even if it has no approved template right now.
  if (value && !options.some((o) => o.code === value)) {
    selectOptions.push({ value, label: value });
  }

  let help = t(
    "whatsapp_language.help",
    "Language of the WhatsApp messages your customers receive."
  );
  if (current && current.code !== "en" && !current.fullyApproved) {
    help = t(
      "whatsapp_language.partial_help",
      "Some messages are still being approved in %{language}; until then they are sent in English.",
      { language: current.name }
    );
  }

  return (
    <Select
      label={t("whatsapp_language.label", "WhatsApp message language")}
      options={selectOptions}
      value={value || "en"}
      onChange={onChange}
      disabled={disabled}
      helpText={help}
    />
  );
}

// Sample values for {{1}}, {{2}}… in previews.
const SAMPLES = ["Ayesha", "#1234", "2,499", "Classic Watch", "Black", "https://example.com/track", "Main Street"];

function fill(text) {
  return String(text || "").replace(/\{\{\s*(\d+)\s*\}\}/g, (_, n) => SAMPLES[(Number(n) - 1) % SAMPLES.length]);
}

function findComponent(components, type) {
  return (components || []).find((c) => String(c?.type || "").toUpperCase() === type);
}

/** WhatsApp-style bubble for an approved translated template. */
export function WhatsappMessagePreview({ components, rtl }) {
  const header = findComponent(components, "HEADER");
  const body = findComponent(components, "BODY");
  const footer = findComponent(components, "FOOTER");
  const buttons = findComponent(components, "BUTTONS")?.buttons || [];
  const mediaHeader = header && ["IMAGE", "VIDEO", "DOCUMENT"].includes(String(header.format || "").toUpperCase());

  return (
    <div style={{ background: "#e5ddd5", borderRadius: 12, padding: 16, maxWidth: 380, marginInline: "auto" }}>
      <div
        dir={rtl ? "rtl" : "ltr"}
        style={{
          background: "#fff",
          borderRadius: 10,
          boxShadow: "0 1px 2px rgba(0,0,0,0.12)",
          overflow: "hidden",
          textAlign: rtl ? "right" : "left",
        }}
      >
        {mediaHeader && (
          <div style={{ background: "#d9d9d9", height: 120, display: "flex", alignItems: "center", justifyContent: "center", color: "#666", fontSize: 12 }}>
            {t("whatsapp_language.image_header", "Product image")}
          </div>
        )}
        {header && !mediaHeader && header.text && (
          <div style={{ padding: "10px 12px 0", fontWeight: 600, fontSize: 14 }}>{fill(header.text)}</div>
        )}
        <div style={{ padding: "8px 12px", fontSize: 14, lineHeight: 1.5, whiteSpace: "pre-wrap", color: "#111" }}>
          {fill(body?.text)}
        </div>
        {footer?.text && <div style={{ padding: "0 12px 8px", fontSize: 12, color: "#667781" }}>{fill(footer.text)}</div>}
        {buttons.map((b, i) => (
          <div key={i} style={{ borderTop: "1px solid #f0f0f0", padding: "9px 12px", textAlign: "center", color: "#00a5f4", fontSize: 14 }}>
            {b.text || b.type}
          </div>
        ))}
      </div>
    </div>
  );
}

/**
 * Preview for one notification: the translated bubble when that template is approved in the shop's
 * language, otherwise the existing English screenshot (with a note when a translation is pending).
 */
export function WhatsappNotificationPreview({ data, language, event, fallbackSrc, alt, imageStyle, imageClassName }) {
  const preview = previewFor(data, language, event);
  if (preview?.approved && preview.components) {
    return <WhatsappMessagePreview components={preview.components} rtl={preview.rtl ?? isRtl(data, language)} />;
  }
  const pendingLanguage = language && language !== "en" ? data?.options?.find((o) => o.code === language) : null;
  return (
    <BlockStack gap="200" inlineAlign="center">
      {fallbackSrc ? <img src={fallbackSrc} alt={alt || ""} className={imageClassName} style={imageStyle} /> : null}
      {pendingLanguage && (
        <Text as="p" variant="bodySm" tone="subdued" alignment="center">
          {t(
            "whatsapp_language.fallback_note",
            "This message is still being approved in %{language}, so it is sent in English for now.",
            { language: pendingLanguage.name }
          )}
        </Text>
      )}
    </BlockStack>
  );
}
