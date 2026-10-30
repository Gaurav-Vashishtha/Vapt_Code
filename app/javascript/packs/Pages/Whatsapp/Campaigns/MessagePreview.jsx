import React from "react";
import { BlockStack, Text } from "@shopify/polaris";
import { t } from "./copy";

export const componentOf = (template, type) =>
  (template?.components || []).find((c) => (c?.type || "").toUpperCase() === type);

export const bodyPlaceholders = (template) => {
  const set = new Set();
  (componentOf(template, "BODY")?.text || "").replace(/\{\{(\d+)\}\}/g, (_m, n) => set.add(Number(n)));
  return Array.from(set).sort((a, b) => a - b);
};

export const hasHeaderVariable = (template) => {
  const header = componentOf(template, "HEADER");
  return !!header && (header.format || "").toUpperCase() === "TEXT" && /\{\{\d+\}\}/.test(header.text || "");
};

export const hasDynamicButton = (template) =>
  (componentOf(template, "BUTTONS")?.buttons || []).some(
    (b) => (b?.type || "").toUpperCase() === "URL" && (b?.url || "").includes("{{")
  );

const headerMediaFormat = (template) => {
  const format = (componentOf(template, "HEADER")?.format || "").toUpperCase();
  return ["IMAGE", "VIDEO", "DOCUMENT"].includes(format) ? format : null;
};

const MEDIA_ICON = { IMAGE: "🖼️", VIDEO: "🎬", DOCUMENT: "📄" };

// A WhatsApp chat bubble for the chosen template. `resolve(position)` returns
// the value a variable takes for the sample recipient ("" when it has none);
// unfilled variables are highlighted so the merchant sees what is missing.
const MessagePreview = ({ template, resolve, resolveHeader, buttonUrl, recipientName }) => {
  if (!template) {
    return (
      <div style={styles.chat}>
        <div style={{ ...styles.bubble, color: "#667781", textAlign: "center" }}>
          {t("preview_empty", "Choose a message to see how it looks on a customer's phone.")}
        </div>
      </div>
    );
  }

  const body = componentOf(template, "BODY")?.text || "";
  const parts = body.split(/(\{\{\d+\}\})/g).map((part) => {
    const m = part.match(/^\{\{(\d+)\}\}$/);
    if (!m) return { text: part };
    const value = resolve(m[1]);
    return value ? { text: value, filled: true } : { text: part, missing: true };
  });

  const header = componentOf(template, "HEADER");
  const headerIsText = (header?.format || "").toUpperCase() === "TEXT" && header?.text;
  const headerText = headerIsText
    ? header.text.replace(/\{\{\d+\}\}/, (resolveHeader && resolveHeader()) || "{{1}}")
    : null;
  const buttons = componentOf(template, "BUTTONS")?.buttons || [];
  const footer = componentOf(template, "FOOTER")?.text;
  const media = headerMediaFormat(template);
  const missing = parts.some((p) => p.missing);

  return (
    <BlockStack gap="200">
      {recipientName && (
        <Text as="p" variant="bodySm" tone="subdued">
          {t("preview_as", "Shown as %{name} would see it", { name: recipientName })}
        </Text>
      )}
      <div style={styles.chat}>
        <div style={styles.bubble}>
          {media && <div style={styles.media}>{MEDIA_ICON[media]}</div>}
          {headerText && <div style={styles.header}>{headerText}</div>}
          <div style={styles.body}>
            {parts.map((part, i) =>
              part.missing ? (
                <span key={i} style={styles.missing}>{part.text}</span>
              ) : part.filled ? (
                <span key={i} style={{ fontWeight: 600 }}>{part.text}</span>
              ) : (
                <React.Fragment key={i}>{part.text}</React.Fragment>
              )
            )}
          </div>
          {footer && <div style={styles.footer}>{footer}</div>}
          <div style={styles.time}>
            {new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
          </div>
          {buttons.map((b, i) => (
            <div key={i} style={styles.button}>
              {(b?.type || "").toUpperCase() === "URL" ? "🔗 " : "↩︎ "}
              {b.text || t("preview_button", "Button")}
            </div>
          ))}
        </div>
        {buttonUrl !== undefined && (
          <div style={{ ...styles.link, color: buttonUrl ? "#54656f" : "#b42318" }}>
            {buttonUrl
              ? t("preview_opens", "Button opens: %{url}", { url: buttonUrl })
              : t("preview_button_missing", "Choose what the button links to")}
          </div>
        )}
      </div>
      {missing && (
        <Text as="p" variant="bodySm" tone="critical">
          {t("preview_missing", "Highlighted parts have no value yet. Fill them in under Personalise.")}
        </Text>
      )}
    </BlockStack>
  );
};

const styles = {
  chat: { background: "#efeae2", borderRadius: 12, padding: "20px 16px" },
  bubble: {
    maxWidth: 340,
    background: "#fff",
    borderRadius: "0 8px 8px 8px",
    boxShadow: "0 1px 1px rgba(0,0,0,.15)",
    padding: 8,
    overflow: "hidden",
  },
  media: {
    background: "#ccd0d5",
    borderRadius: 6,
    height: 120,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: 32,
    marginBottom: 6,
  },
  header: { fontWeight: 700, fontSize: 14, color: "#111b21", marginBottom: 4 },
  body: { fontSize: 13.5, color: "#111b21", whiteSpace: "pre-wrap", lineHeight: "19px" },
  missing: { background: "#fff1e3", color: "#8e1f0b", fontWeight: 600, borderRadius: 3, padding: "0 2px" },
  footer: { fontSize: 12, color: "#667781", marginTop: 4 },
  time: { fontSize: 11, color: "#667781", textAlign: "right", marginTop: 2 },
  button: {
    borderTop: "1px solid #e9edef",
    marginTop: 6,
    paddingTop: 8,
    paddingBottom: 2,
    textAlign: "center",
    color: "#027eb5",
    fontSize: 13.5,
    fontWeight: 500,
  },
  link: { fontSize: 12, marginTop: 8, maxWidth: 340, wordBreak: "break-all" },
};

export default MessagePreview;
