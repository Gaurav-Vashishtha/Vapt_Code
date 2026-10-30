import React, { useContext, useMemo, useState, useEffect } from "react";
import { Card, BlockStack, InlineStack, Text, Button } from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";

const THEMES = {
  theme1: { primary: "#c20000", primaryDark: "#b91c1c", secondary: "#ffffff", background: "#ffffff", cardBg: "#fff1f2", text: "#333333", border: "#e5e7eb" },
  theme2: { primary: "#2563eb", primaryDark: "#1d4ed8", secondary: "#ffffff", background: "#f1f5f9", cardBg: "#e0f2fe", text: "#1f2937", border: "#cbd5e1" },
  theme3: { primary: "#10b981", primaryDark: "#047857", secondary: "#ffffff", background: "#f9fafb", cardBg: "#d1fae5", text: "#374151", border: "#d1d5db" },
  theme4: { primary: "#f59e0b", primaryDark: "#d97706", secondary: "#ffffff", background: "#ffffff", cardBg: "#ffedd5", text: "#4b5563", border: "#e2e8f0" },
  theme5: { primary: "#123646", primaryDark: "#000713", secondary: "#FFFFFF", background: "#F6F8FA", cardBg: "#E9EEF2", text: "#1E1E1E", border: "#D9DEE3" },
  theme6: { primary: "#f87171", primaryDark: "#ef4444", secondary: "#FFFFFF", background: "#ffffff", cardBg: "#fee2e2", text: "#374151", border: "#e5e7eb" },
  crimsonTheme: { primary: "rgb(145, 14, 64)", primaryDark: "rgb(115, 11, 50)", secondary: "#ffffff", background: "rgb(255, 249, 252)", cardBg: "rgb(255, 235, 238)", text: "rgb(28, 27, 31)", border: "rgb(220, 38, 126)" },
  minimalWhiteTheme: { primary: "#123646", primaryDark: "#000713", secondary: "#FFFFFF", background: "#F6F8FA", cardBg: "#E9EEF2", text: "#1E1E1E", border: "#D9DEE3" },
  luxeGoldTheme: { primary: "#d4af37", primaryDark: "#b2942d", secondary: "#ffffff", background: "#ffffff", cardBg: "#fafafa", text: "#333333", border: "#d4af37" },
  freshGreenTheme: { primary: "#228b22", primaryDark: "#1e7b1e", secondary: "#ffffff", background: "#f5fff5", cardBg: "#e6f7e6", text: "#1e3a24", border: "#d1e7d1" },
  theme7: { primary: "#ad5389", primaryDark: "#3c1053", secondary: "#f5f5f5", background: "#fafafa", cardBg: "#ffffff", text: "#333333", border: "#b38cb4" },
  theme8: { primary: "#3d0c02", primaryDark: "#b92e34", secondary: "#f2dfd5", background: "#fffaf5", cardBg: "#fdf1eb", text: "#2e1c15", border: "#9c4f38" },
  theme9: { primary: "#9a4622", primaryDark: "#bf5e35", secondary: "#ffffff", background: "#ffffff", cardBg: "#f0f0f0", text: "#000000", border: "#d1d1d1" },
  theme10: { primary: "#EF3D75", primaryDark: "#24010c", secondary: "#ffffff", background: "#ffffff", cardBg: "#f0f0f0", text: "#000000", border: "#d1d1d1" },
  theme11: { primary: "#4B2C5E", primaryDark: "#3A234B", secondary: "#e3cbf4", background: "#F6F8FA", cardBg: "#ffffff", text: "#1E1E1E", border: "#D9DEE3" },
  theme12: { primary: "#ffd247", primaryDark: "#b58906", secondary: "#fffcf4", background: "#ffffff", cardBg: "#f0f0f0", text: "#000000", border: "#d1d1d1" },
  theme13: { primary: "rgb(218 118 141)", primaryDark: "rgb(191 96 121)", secondary: "#FFFFFF", background: "#F6F8FA", cardBg: "#E9EEF2", text: "#1E1E1E", border: "#D9DEE3" },
  themeBlackWhite: { primary: "#000000", primaryDark: "#0a0a0a", secondary: "#FFFFFF", background: "#FFFFFF", cardBg: "#F9F9F9", text: "#000000", border: "#E0E0E0" },
  deepForestTheme: { primary: "#1b3022", primaryDark: "#132319", secondary: "#ffffff", background: "#f4f7f5", cardBg: "#ffffff", text: "#1b3022", border: "#d1dcd4" },
  modernBotanicalTheme: { primary: "#0a3d34", primaryDark: "#052923", secondary: "#ffffff", background: "#fafaf9", cardBg: "#f1f3f1", text: "#121a11", border: "#e2e8e2" },
};

// Mirrors notifik-svelte-app/src/app.css so the preview matches the widget.
const WIDGET = {
  font: '"Metropolis", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
  radiusBase: 8,
  radiusMd: 12,
  shadowCardSoft:
    "0 1px 2px rgba(16, 24, 40, 0.05), 0 6px 16px rgba(16, 24, 40, 0.06)",
  hairline: "#eceff4",
  textMuted: "#7e7e7e",
  surfacePage: "#f9fafd",
  placeholder: "#d4d4d4",
};
// Same files the storefront widget loads.
const ASSET = {
  bolt: "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/Bolt_2.svg?v=1785233574",
  discount:
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/discount_icon-ezgif.com-resize_1.gif?v=1784542496",
  whatsapp:
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/whatsapp.svg?v=1785132359",
  arrow:
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/arrowIconCard.svg?v=1785234513",
  celebration:
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/CelebrationEmoji.png?v=1784797043",
  codking:
    "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/CKlogoicon-1200px_1.png?v=1762758841",
};

const EDITABLE_CSS = `
.codk-editable {
  outline: none;
  border-radius: 4px;
  cursor: text;
  transition: background-color 120ms ease, box-shadow 120ms ease;
}
.codk-editable:hover {
  background: rgba(99, 102, 241, 0.08);
  box-shadow: 0 0 0 2px rgba(99, 102, 241, 0.08);
}
.codk-editable:focus {
  background: rgba(99, 102, 241, 0.10);
  box-shadow: 0 0 0 2px rgba(99, 102, 241, 0.45);
}
`;

const METROPOLIS_CSS =
  "https://cdn.jsdelivr.net/npm/@fontsource/metropolis@5.3.0/500.css";

const CURRENCY = { INR: "₹", USD: "$", EUR: "€", GBP: "£", AED: "د.إ", PKR: "₨", BDT: "৳", NPR: "₨", LKR: "₨", SAR: "﷼" };

// Mirrors notifik-svelte-app/src/utils/codFormConfig.js.
const COD_FORM_DEFAULT_PLACEHOLDERS = {
  name: "e.g. Rahul Sharma",
  pincode: "e.g. 110001",
  city: "e.g. New Delhi",
  state: "e.g. Delhi",
  email: "e.g. rahul@gmail.com",
  address1: "e.g. MG Road, Sector 14",
  address2: "e.g. Flat 302, Green Apartments",
};

function codFormConfig(setting) {
  const cfg = setting?.codFormConfig || setting?.cod_form_config || {};
  const labels = cfg.labels || {};
  const placeholders = cfg.placeholders || {};
  const gst = cfg.gst || {};
  return {
    labels: Object.fromEntries(
      Object.keys(COD_FORM_DEFAULT_PLACEHOLDERS).map((key) => [
        key,
        (labels[key] && String(labels[key]).trim()) || "",
      ]),
    ),
    placeholders: Object.fromEntries(
      Object.entries(COD_FORM_DEFAULT_PLACEHOLDERS).map(([key, fallback]) => [
        key,
        (placeholders[key] && String(placeholders[key]).trim()) || fallback,
      ]),
    ),
    gst: {
      enabled: gst.enabled === true,
      label: (gst.label && String(gst.label).trim()) || "GST Number",
      placeholder:
        (gst.placeholder && String(gst.placeholder).trim()) ||
        "e.g. 22AAAAA0000A1Z5",
    },
  };
}

function resolveTheme(setting) {
  const t = setting?.preV2Theme;
  if (t && typeof t === "object") return { ...THEMES.theme1, ...t };
  if (typeof t === "string" && THEMES[t]) return THEMES[t];
  return THEMES.theme1;
}

function s(setting, key, fallback) {
  const v = setting?.[key];
  return v == null || v === "" ? fallback : v;
}

function formatTitle(str) {
  if (!str) return "COD King";
  return String(str)
    .toLowerCase()
    .split(" ")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

// The three screens the customization tabs map onto. Always shown, even when a
// feature is off, so merchants can see what they are editing.
function buildSteps(setting) {
  const steps = [
    { key: "phone", label: I18n.t("checkout_form_preview.login") },
    { key: "otp", label: I18n.t("checkout_form_preview.verify") },
  ];
  if (setting?.isPrefilledAddressEnabled) steps.push({ key: "address", label: I18n.t("checkout_form_preview.address") });
  steps.push({ key: "payment", label: I18n.t("checkout_form_preview.payments") });
  steps.push({ key: "done", label: I18n.t("checkout_form_preview.done") });
  return steps;
}

const CheckoutFormPreview = ({
  setting: settingProp,
  screen,
  onEditText,
  onEditSetting,
}) => {
  const ctx = useContext(StoreContext);
  const setting = settingProp || ctx?.setting?.[0] || {};
  const shop = ctx?.shop?.[0] || {};

  const theme = useMemo(() => resolveTheme(setting), [setting]);

  useEffect(() => {
    const id = "codk-preview-editable-css";
    if (!document.getElementById(id)) {
      const style = document.createElement("style");
      style.id = id;
      style.textContent = EDITABLE_CSS;
      document.head.appendChild(style);
    }
  }, []);

  useEffect(() => {
    const id = "codk-preview-metropolis";
    if (document.getElementById(id)) return;
    const link = document.createElement("link");
    link.id = id;
    link.rel = "stylesheet";
    link.href = METROPOLIS_CSS;
    document.head.appendChild(link);
  }, []);
  const cur = CURRENCY[shop?.currency] || CURRENCY.INR;
  const money = (n) => `${cur}${Number(n).toLocaleString("en-IN")}`;

  const [rules, setRules] = useState([]);
  useEffect(() => {
    if (!setting?.partialPaymentEnabled) {
      setRules([]);
      return undefined;
    }
    let cancelled = false;
    Api.get("/partial_rule_sets")
      .then((res) => {
        const list = Array.isArray(res?.data) ? res.data : [];
        if (!cancelled) {
          setRules(
            list
              .filter((r) => r.isEnabled !== false)
              .sort((a, b) => (a.position || 0) - (b.position || 0)),
          );
        }
      })
      .catch(() => {
        if (!cancelled) setRules([]);
      });
    return () => {
      cancelled = true;
    };
  }, [setting?.partialPaymentEnabled]);

  const editableNode = (id, current, fallback, commit) => {
    const shown = current || fallback;
    if (!commit) return shown;
    return (
      <span
        key={`${id}:${current}`}
        className="codk-editable"
        role="textbox"
        tabIndex={0}
        contentEditable
        suppressContentEditableWarning
        title={I18n.t("checkout_form_preview.click_to_edit")}
        onBlur={(event) => {
          const next = event.currentTarget.textContent.trim();
          if (next !== shown) commit(next);
        }}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault();
            event.currentTarget.blur();
          }
          if (event.key === "Escape") {
            event.currentTarget.textContent = shown;
            event.currentTarget.blur();
          }
        }}
      >
        {shown}
      </span>
    );
  };

  // Strings stored in ui_customization.texts.
  const editable = (key, fallback) =>
    editableNode(
      key,
      uiTexts[key] ?? "",
      fallback,
      onEditText ? (next) => onEditText(key, next) : null,
    );

  // Strings the widget still reads from their own settings column.
  const editableSetting = (key, fallback) =>
    editableNode(
      key,
      setting?.[key] ?? "",
      fallback,
      onEditSetting ? (next) => onEditSetting(key, next) : null,
    );

  const steps = useMemo(() => buildSteps(setting), [setting]);
  const [active, setActive] = useState(0);
  // The widget shows the order summary as a sheet that opens over the payment
  // step. It stays shut here until the merchant edits order-summary copy,
  // otherwise half those fields have nowhere on screen to appear.
  const [summaryOpen, setSummaryOpen] = useState(false);
  useEffect(() => {
    if (active > steps.length - 1) setActive(0);
  }, [steps.length, active]);

  // Editing the Login tab should show the login screen, and so on.
  useEffect(() => {
    if (!screen) return;
    // Order-summary copy lives on the payment step, inside the sheet.
    const key = screen === "order-summary" ? "payment" : screen;
    const idx = steps.findIndex((st) => st.key === key);
    if (idx >= 0) setActive(idx);
    setSummaryOpen(screen === "order-summary");
  }, [screen, steps]);
  const current = steps[Math.min(active, steps.length - 1)] || steps[0];

  const brandTitle = formatTitle(s(setting, "preV2Title", shop?.name || "COD King"));
  const brandLogo = setting?.brandLogoUrl;
  const hideFooterBranding =
    (setting?.uiCustomization || setting?.ui_customization || {})?.branding
      ?.hide_footer_branding === true;
  const showBranding = setting?.preShowBranding !== false && !hideFooterBranding;
  const showOrderSummary = setting?.preV2ShowOrderSummary !== false;
  const showWhatsapp = !!setting?.preWhatsappButton;
  const showSkip = setting?.preShowSkipBtn !== false;

  // Merchant copy overrides (ui_customization.texts), same source the widget reads.
  const uiTexts =
    setting?.uiCustomization?.texts || setting?.ui_customization?.texts || {};

  const primaryBg = s(setting, "prePrimaryButtonColor", "#0e0e0e");
  const primaryFg = s(setting, "prePrimaryButtonFontColor", "#ffffff");

  const showPromo = setting?.promoBannerShow !== false && !!setting?.promoBannerText;
  const promoBg = s(setting, "promoBannerColor", "#dc2626");
  const promoFg = s(setting, "promoTextColor", "#ffffff");

  const subtotal = 600;
  // Two, so "Word for several items" is visible in the preview; the sample line
  // below still reads Qty 1.
  const itemCount = 2;
  const shippingFee = 0;
  const taxAmount = 54;
  const discountRule = rules.find((r) => Number(r.discountValue) > 0);
  const discount = discountRule
    ? discountRule.discountType === "percentage"
      ? Math.round((subtotal * Number(discountRule.discountValue)) / 100)
      : Math.round(Number(discountRule.discountValue))
    : 0;
  const total = subtotal - discount;
  const hasDisc = discount > 0;

  const computeRule = (rule) => {
    const amount = Number(rule.amount) || 0;
    const isPct = (rule.amountType || "percentage") === "percentage";
    const codFee =
      rule.includeCodFee && Number(rule.codFeeAmount) > 0
        ? Math.round(Number(rule.codFeeAmount))
        : 0;
    let payNow;
    let desc;
    if (isPct && amount >= 100) {
      payNow = total + codFee;
      desc = `Order total is ${money(total)}${
        codFee ? ` (+ ${money(codFee)} COD fee)` : ""
      }.`;
    } else {
      payNow = isPct ? Math.round((total * amount) / 100) : Math.round(amount);
      payNow += codFee;
      desc = `Pay ${money(payNow)} now and ${money(
        Math.max(total - (payNow - codFee), 0),
      )} on delivery.`;
    }
    const badges = [];
    if (codFee) badges.push({ text: `${money(codFee)} COD fee added`, color: "#dc2626" });
    const customSave = String(rule.customSaveText || "").trim();
    if (customSave) {
      badges.push({ text: customSave, color: "#059669" });
    } else if (Number(rule.discountValue) > 0) {
      const d =
        rule.discountType === "percentage"
          ? `Save ${Number(rule.discountValue)}%`
          : `Save ${money(Math.round(Number(rule.discountValue)))}`;
      badges.push({ text: d, color: "#059669" });
    }
    return { title: rule.ruleName || "Payment option", price: money(payNow), desc, badges };
  };

  /* ---------------------------------------------------------------------
     Presentation mirrors notifik-svelte-app: ScreenHeader.css (white 52px
     bar, centred uppercase brand), OrderSummaryCard.css / PaymentOptions
     Section.css (white cards, #d0dbf726 shadow, dashed hairline rows) and
     ContinueButtonWithFooter.css (black CTA in a sticky white footer).
     --------------------------------------------------------------------- */
  const W = {
    font: WIDGET.font,
    page: "#f9fafd",
    card: "#ffffff",
    hairline: "#eceff4",
    text: "#2f2f2f",
    muted: "#7e7e7e",
    placeholder: "#d4d4d4",
    savings: "#238017",
    cardShadow: "4px 4px 11px 0 #d0dbf726, -2px -2px 10px 0 #d0dbf726",
  };

  const sectionCard = (children, extra = {}) => (
    <div
      style={{
        background: W.card,
        borderRadius: 12,
        boxShadow: W.cardShadow,
        overflow: "hidden",
        marginBottom: 12,
        ...extra,
      }}
    >
      {children}
    </div>
  );

  // .continue-button — black by default, overridden by the merchant's colour.
  const primaryBtn = (label) => (
    <div
      style={{
        background: primaryBg || "#000000",
        color: primaryFg,
        textAlign: "center",
        borderRadius: 6,
        padding: "13px 16px",
        fontSize: 15,
        fontWeight: 600,
        boxShadow: "0px 1px 4px 0px rgba(25, 33, 61, 0.08)",
      }}
    >
      {label}
    </div>
  );

  // .continue-button-footer-container
  const footer = (children) => (
    <div
      style={{
        background: W.card,
        borderTop: `1px solid ${W.hairline}`,
        padding: "12px 14px",
        display: "flex",
        flexDirection: "column",
        gap: 8,
      }}
    >
      {children}
    </div>
  );

  const brandFooter = () =>
    showBranding && (
      <div style={{ textAlign: "center", fontSize: 10, color: W.muted, lineHeight: "14px" }}>
        <span style={{ color: W.placeholder }}>
          {uiTexts.legal_terms || "T&C"} | {uiTexts.legal_privacy || "Privacy Policy"}
        </span>
        <div style={{ marginTop: 3, fontWeight: 600, display: "flex", alignItems: "center", justifyContent: "center", gap: 4 }}>
          <img src={ASSET.codking} alt="" style={{ width: 12, height: 12, objectFit: "contain" }} />
          {I18n.t("checkout_form_preview.powered_by_cod_king")}
        </div>
      </div>
    );

  const summaryRow = (label, value, tone) => (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: 12,
        fontSize: 13,
        color: tone || W.muted,
        marginBottom: 8,
      }}
    >
      <span style={{ minWidth: 0 }}>{label}</span>
      <span style={{ color: tone || W.text, whiteSpace: "nowrap" }}>{value}</span>
    </div>
  );

  // .order-summary-unit
  const OrderSummary = () => (
    <div style={{ borderRadius: 12, overflow: "hidden", boxShadow: W.cardShadow, marginBottom: 12 }}>
      <div style={{ background: W.card, padding: 14 }}>
        <div
          onClick={() => setSummaryOpen((v) => !v)}
          style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, cursor: "pointer" }}
        >
          <div style={{ display: "flex", alignItems: "baseline", gap: 6, minWidth: 0 }}>
            <span style={{ fontSize: 16, lineHeight: "22px", fontWeight: 600, color: W.text }}>
              {editable("order_summary_title", "Order summary")}
            </span>
            <span style={{ fontSize: 12, color: W.muted }}>
              {itemCount}{" "}
              {itemCount === 1
                ? uiTexts.item_singular || "item"
                : uiTexts.item_plural || "items"}
            </span>
          </div>
          <img
            src={ASSET.arrow}
            alt=""
            style={{
              width: 16,
              height: 16,
              opacity: 0.5,
              transform: summaryOpen ? "rotate(180deg)" : "none",
              transition: "transform 160ms ease",
            }}
          />
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 12 }}>
          <div style={{ width: 44, height: 44, borderRadius: 8, background: "#f2f4f8", flexShrink: 0 }} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 14, fontWeight: 600, color: W.text }}>{I18n.t("checkout_form_preview.sample_product")}</div>
            <div style={{ fontSize: 12, color: W.muted, marginTop: 2 }}>
              {(uiTexts.qty || "Qty {{count}}").replace("{{count}}", "1")}
            </div>
          </div>
          <div style={{ textAlign: "right" }}>
            {hasDisc && (
              <div style={{ fontSize: 12, color: W.muted, textDecoration: "line-through" }}>
                {money(subtotal)}
              </div>
            )}
            <div style={{ fontSize: 16, fontWeight: 700, color: W.text }}>{money(total)}</div>
          </div>
        </div>
      </div>

      {summaryOpen && (
        <div style={{ background: W.card, borderTop: `1px solid ${W.border || "#e6e8eb"}`, padding: 14 }}>
          <div style={{ fontSize: 14, fontWeight: 600, color: W.text, marginBottom: 10 }}>
            {editable("billing_summary_title", "Bill details")}
          </div>

          {summaryRow(editable("subtotal", "Subtotal"), money(subtotal))}

          {hasDisc &&
            summaryRow(
              editable("discount", "Discount"),
              `- ${money(discount)}`,
              W.savings,
            )}
          {hasDisc &&
            summaryRow(
              (uiTexts.discount_with_name || "Discount ({{name}})").replace(
                "{{name}}",
                discountRule?.ruleName || "SAVE10",
              ),
              `- ${money(discount)}`,
              W.savings,
            )}
          {hasDisc &&
            summaryRow(
              editable("discount_on_mrp", "Discount on MRP"),
              `- ${money(discount)}`,
              W.savings,
            )}

          {summaryRow(
            editable("shipping", "Shipping"),
            shippingFee > 0
              ? money(shippingFee)
              : editable("shipping_value", "Free"),
          )}

          {summaryRow(editable("tax", "Tax"), money(taxAmount))}
          <div style={{ fontSize: 11, color: W.muted, marginTop: -4, marginBottom: 8 }}>
            {setting?.isTaxIncludedWithProduct === false
              ? editable("tax_excluded_note", "Tax not included in price")
              : editable("tax_included_note", "Tax included in price")}
          </div>

          <div style={{ borderTop: `1px solid ${W.border || "#e6e8eb"}`, marginTop: 4, paddingTop: 10 }}>
            {summaryRow(
              <span style={{ fontWeight: 700, color: W.text }}>
                {editable("total_amount", "Total amount")}
              </span>,
              <span style={{ fontWeight: 700, color: W.text }}>{money(total)}</span>,
            )}
          </div>

          {/* Only reachable with an empty cart, which the sample never is, so it
              is shown here as a muted note rather than left with no preview. */}
          <div style={{ fontSize: 11, color: W.muted, marginTop: 10, fontStyle: "italic" }}>
            {editable("no_items_in_cart", "No items in cart")}
          </div>
        </div>
      )}

      {hasDisc && (
        <div
          style={{
            background: "#e7f4ea",
            color: W.savings,
            padding: "8px 14px",
            fontSize: 12,
            fontWeight: 600,
            display: "flex",
            alignItems: "center",
            gap: 6,
          }}
        >
          ✓ {(uiTexts.saved_so_far || "You saved {{amount}}").replace("{{amount}}", money(discount))}
        </div>
      )}
    </div>
  );

  const renderStep = () => {
    if (current.key === "phone") {
      return (
        <>
          <div style={{ padding: "16px 2px 14px" }}>
            <div style={{ fontSize: 18, fontWeight: 600, color: W.text, lineHeight: "24px" }}>
              {editable("phone_title", s(setting, "preHeading", "Enter mobile number"))}
            </div>
            <div style={{ fontSize: 13, color: W.muted, marginTop: 4, lineHeight: "18px" }}>
              {editable(
                "phone_subtitle",
                s(setting, "preSubHeading", "Provide your mobile number to continue"),
              )}
            </div>
          </div>

          {/* .phone-input-wrapper */}
          <div
            style={{
              display: "flex",
              alignItems: "stretch",
              background: W.card,
              border: `1px solid ${W.hairline}`,
              borderRadius: 8,
              overflow: "hidden",
              boxShadow: W.cardShadow,
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 6,
                padding: "13px 12px",
                borderRight: `1px solid ${W.hairline}`,
                fontSize: 14,
                fontWeight: 600,
                color: W.text,
              }}
            >
              🇮🇳 +91 <span style={{ color: W.muted, fontSize: 10 }}>▾</span>
            </div>
            <div style={{ flex: 1, padding: "13px 12px", fontSize: 14, color: W.placeholder }}>
              {editableSetting("prePhonePlaceholder", "Enter phone number")}
            </div>
          </div>
        </>
      );
    }

    if (current.key === "otp") {
      return (
        <>
          <div style={{ padding: "16px 2px 14px" }}>
            <div style={{ fontSize: 18, fontWeight: 600, color: W.text, lineHeight: "24px" }}>
              {editableSetting("preVerifyMobile", "Verify your number")}
            </div>
            <div style={{ fontSize: 13, color: W.muted, marginTop: 4 }}>
              {editableSetting("preEnterCode", "Enter the code sent to")} +91 98765 43210
            </div>
          </div>

          <div style={{ display: "flex", gap: 10, marginBottom: 16 }}>
            {[0, 1, 2, 3].map((i) => (
              <div
                key={i}
                style={{
                  flex: 1,
                  height: 52,
                  background: W.card,
                  border: `1px solid ${i === 0 ? W.text : W.hairline}`,
                  borderRadius: 8,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 20,
                  fontWeight: 600,
                  color: W.text,
                  boxShadow: W.cardShadow,
                }}
              >
                {i < 2 ? "•" : ""}
              </div>
            ))}
          </div>

          <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 6, fontSize: 13, color: W.muted }}>
            <span>{editable("otp_resend_via", "Resend OTP via")}</span>
            <span style={{ color: W.text, fontWeight: 600 }}>
              {editable("otp_channel_sms", "SMS")}
            </span>
          </div>
        </>
      );
    }

    if (current.key === "address") {
      // Mirrors AddressForm.svelte: label falls back from the copy catalog to
      // the COD form config to a default, and the box shows its placeholder.
      const cfg = codFormConfig(setting);
      const field = (textKey, cfgKey, fallbackLabel) => ({
        label: uiTexts[textKey] || cfg.labels[cfgKey] || fallbackLabel,
        placeholder: cfg.placeholders[cfgKey],
      });
      const fields = [
        field("addr_pincode", "pincode", "Pincode"),
        field("addr_first_name", "name", "Full name"),
        field("addr_line1", "address1", "Address"),
        field("addr_city", "city", "City"),
        field("addr_state", "state", "State"),
      ];
      if (cfg.gst.enabled) {
        fields.push({ label: cfg.gst.label, placeholder: cfg.gst.placeholder });
      }

      return (
        <>
          <div style={{ padding: "16px 2px 14px" }}>
            <div style={{ fontSize: 18, fontWeight: 600, color: W.text }}>
              {editable("addr_type_title", "Delivery address")}
            </div>
          </div>
          {sectionCard(
            <div style={{ padding: 14 }}>
              {fields.map((f, i) => (
                <div key={f.label + i} style={{ marginTop: i === 0 ? 0 : 10 }}>
                  {f.label && (
                    <div
                      style={{
                        fontSize: 12,
                        fontWeight: 500,
                        color: W.muted,
                        marginBottom: 4,
                      }}
                    >
                      {f.label}
                    </div>
                  )}
                  <div
                    style={{
                      border: `1px solid ${W.hairline}`,
                      borderRadius: 8,
                      padding: "13px 12px",
                      fontSize: 14,
                      color: W.placeholder,
                    }}
                  >
                    {f.placeholder}
                  </div>
                </div>
              ))}
            </div>,
          )}
        </>
      );
    }

    if (current.key === "payment") {
      const list = rules.length > 0 ? rules.map(computeRule) : FALLBACK_OPTIONS(money, total);
      return (
        <>
          {showOrderSummary && <OrderSummary />}

          {/* .payment-options-section */}
          {sectionCard(
            <>
              <div style={{ padding: "14px 14px 12px", display: "flex", flexDirection: "column", gap: 2 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 4, color: W.muted, fontSize: 12, fontWeight: 500, lineHeight: "16px" }}>
                  <img src={ASSET.bolt} alt="" style={{ height: 12, width: "auto", flexShrink: 0 }} />
                  {editable("payment_options_perk", "Enjoy fast delivery on all prepaid orders")}
                </div>
                <div style={{ fontSize: 16, fontWeight: 600, color: W.text, lineHeight: "20px", letterSpacing: "-0.2px" }}>
                  {editable("payment_options_title", "Pay via")}
                </div>
              </div>

              <div>
                {list.map((opt, i) => (
                  <PayOption key={i} opt={opt} selected={i === 0} W={W} first={i === 0} />
                ))}
              </div>
            </>,
          )}
        </>
      );
    }

    return (
      <div style={{ textAlign: "center", padding: "28px 12px" }}>
        <img src={ASSET.celebration} alt="" style={{ width: 48, height: 48 }} />
        <div style={{ fontSize: 17, fontWeight: 600, color: W.text, marginTop: 8 }}>
          {editable("oc_thank_you", "Thank you!")}
        </div>
        <div style={{ fontSize: 13, color: W.muted, marginTop: 4 }}>
          {editable("oc_placed", "Your order has been placed.")}
        </div>
      </div>
    );
  };

  const ctaLabel =
    current.key === "phone"
      ? editableSetting("preSendButtonLabel", "Get OTP")
      : current.key === "otp"
        ? s(setting, "preVerifyButtonLabel", "Verify")
        : current.key === "payment"
          ? editable("cta_proceed", "Proceed to Payment")
          : editable("cta_close", "Close");

  return (
    <Card>
      <BlockStack gap="300">
        <Text variant="bodySm" tone="subdued" as="p">
          {onEditText
            ? "For demonstration only, your live widget may look different. Click any text to edit it."
            : "For demonstration only, your live widget may look different."}
        </Text>

        <InlineStack gap="150" wrap>
          {steps.map((st, i) => (
            <Button key={st.key} size="micro" pressed={i === active} onClick={() => setActive(i)}>
              {st.label}
            </Button>
          ))}
        </InlineStack>

        {/* Device frame around the widget sheet */}
        <div
          style={{
            border: "8px solid #111827",
            borderRadius: 26,
            overflow: "hidden",
            maxWidth: 420,
            margin: "0 auto",
            width: "100%",
            boxShadow: "0 10px 30px rgba(0,0,0,0.18)",
            fontFamily: W.font,
            background: W.page,
            display: "flex",
            flexDirection: "column",
            minHeight: 460,
          }}
        >
          {/* .screen-header — white, centred brand, close on the right */}
          <div style={{ background: W.card, borderBottom: `1px solid ${W.hairline}`, flexShrink: 0 }}>
            <div
              style={{
                position: "relative",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                height: 52,
                padding: "0 48px",
                gap: 8,
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 0 }}>
                {brandLogo ? (
                  <img
                    src={brandLogo}
                    alt=""
                    style={{ width: 28, height: 28, borderRadius: 8, objectFit: "contain" }}
                  />
                ) : null}
                <span
                  style={{
                    fontSize: 15,
                    lineHeight: "20px",
                    fontWeight: 600,
                    letterSpacing: "0.04em",
                    textTransform: "uppercase",
                    color: W.text,
                    whiteSpace: "nowrap",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                  }}
                >
                  {brandTitle}
                </span>
              </div>
              <span
                style={{
                  position: "absolute",
                  right: 8,
                  top: "50%",
                  transform: "translateY(-50%)",
                  width: 34,
                  height: 34,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  color: W.muted,
                  fontSize: 18,
                }}
              >
                ✕
              </span>
            </div>

            {showPromo && (
              <div
                style={{
                  background: promoBg,
                  color: promoFg,
                  textAlign: "center",
                  padding: "8px 12px",
                  fontSize: 12,
                  fontWeight: 600,
                }}
              >
                {setting.promoBannerText}
              </div>
            )}
          </div>

          {/* .screen-content */}
          <div style={{ flex: 1, padding: "0 14px 14px", background: W.page, overflow: "hidden" }}>
            {renderStep()}
          </div>

          {current.key !== "done" &&
            footer(
              <>
                {primaryBtn(ctaLabel)}
                {current.key === "phone" && showWhatsapp && (
                  <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 8, fontSize: 13, color: W.muted }}>
                    <span>{editable("phone_send_otp_via", "Send OTP via")}</span>
                    <img src={ASSET.whatsapp} alt={I18n.t("checkout_form_preview.whatsapp")} style={{ width: 22, height: 22 }} />
                  </div>
                )}
                {current.key === "phone" && showSkip && (
                  <div style={{ textAlign: "center", fontSize: 13, textDecoration: "underline", color: W.text }}>
                    {s(setting, "preSkipBtnText", "Skip and place Non-COD Order")}
                  </div>
                )}
                {brandFooter()}
              </>,
            )}
        </div>
      </BlockStack>
    </Card>
  );
};

// .payment-option-card — dashed hairline rows, square radio, no boxed card.
function PayOption({ opt, selected, W, first }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 12,
        padding: "12px 8px",
        minHeight: 60,
        background: "#ffffff",
        borderTop: first ? `2px dashed ${W.hairline}` : 0,
        borderBottom: `2px dashed ${W.hairline}`,
      }}
    >
      <span
        style={{
          position: "relative",
          width: 26,
          height: 26,
          borderRadius: 6,
          border: `1px solid ${selected ? "rgba(37,99,235,0.5)" : "rgba(37,99,235,0.2)"}`,
          background: "#fff",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexShrink: 0,
        }}
      >
        {selected && (
          <span style={{ width: 12, height: 12, borderRadius: 4, background: "#2563eb", display: "block" }} />
        )}
      </span>

      <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 4, minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
          <span style={{ color: W.text, fontSize: 14, fontWeight: 650, lineHeight: "18px" }}>
            {opt.title}
          </span>
          {opt.badges.map((b, i) =>
            b.color === "#059669" ? (
              /* .option-save-line — the animated discount mark plus green copy */
              <span
                key={i}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 4,
                  color: "#238017",
                  fontSize: 12,
                  fontWeight: 500,
                  lineHeight: "16px",
                }}
              >
                <img src={ASSET.discount} alt="" style={{ height: 14, width: "auto", flexShrink: 0 }} />
                {b.text}
              </span>
            ) : (
              <span key={i} style={{ fontSize: 11, fontWeight: 600, color: b.color }}>
                {b.text}
              </span>
            ),
          )}
        </div>
        <div style={{ fontSize: 12, color: W.muted, lineHeight: "16px" }}>{opt.desc}</div>
      </div>

      <span style={{ fontSize: 15, fontWeight: 700, color: W.text, flexShrink: 0 }}>{opt.price}</span>
    </div>
  );
}

const FALLBACK_OPTIONS = (money, total) => [
  {
    title: I18n.t("checkout_form_preview.full_payment"),
    price: money(total),
    desc: `Order total is ${money(total)}.`,
    badges: [],
  },
  {
    title: I18n.t("checkout_form_preview.cash_on_delivery"),
    price: money(total),
    desc: `Pay ${money(total)} on delivery.`,
    badges: [],
  },
];

export default CheckoutFormPreview;
