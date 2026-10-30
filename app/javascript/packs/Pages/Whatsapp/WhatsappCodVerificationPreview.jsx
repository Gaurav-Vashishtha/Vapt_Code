import React, { useEffect, useState } from "react";
import I18n from "../../i18n-lang";

/**
 * The whole customer journey for a COD verification, end to end.
 *
 * It opens on the WhatsApp message the customer actually receives, styled like
 * the template previews elsewhere in the app. Tapping the template button is
 * what takes them to /order/verify, so the preview does the same: the message
 * leads into the verify page, and confirm and cancel move through the states
 * that page really has.
 *
 * It mirrors order_verify_react rather than embedding it, because that page
 * needs a real OrderConfirmation row and posts to /order_confirmations/confirm
 * and /cancel. Nothing here is sent and no order changes.
 */
const DEMO = {
  storeName: "Demo Store",
  customer: "Ram Sharma",
  orderNumber: "1234",
  amount: "₹1,199.00",
};

const t = (key, fallback) => {
  const value = I18n.t(`admin.${key}`, { defaultValue: "" });
  return value && value !== `admin.${key}` ? value : fallback;
};

const CHAT_PAPER =
  "linear-gradient(0deg, rgba(255,255,255,0.55), rgba(255,255,255,0.55)), #efeae2";

const Outcome = ({ tone, title, message, onRestart }) => (
  <div style={{ padding: "28px 20px", textAlign: "center" }}>
    <div
      style={{
        width: 44,
        height: 44,
        borderRadius: "50%",
        margin: "0 auto 12px",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontSize: 22,
        background: tone === "ok" ? "#e3f5e9" : "#fdeced",
        color: tone === "ok" ? "#0c7c3e" : "#c62828",
      }}
      aria-hidden="true"
    >
      {tone === "ok" ? "✓" : "✕"}
    </div>
    <div style={{ fontSize: 15, fontWeight: 650, color: "#202223" }}>{title}</div>
    <div style={{ fontSize: 13, color: "#6d7175", marginTop: 6 }}>{message}</div>
    <button type="button" onClick={onRestart} style={linkButton}>
      {I18n.t("whatsapp_cod_verification_preview.start_over")}
    </button>
  </div>
);

const quickReply = {
  width: "100%",
  padding: "10px 12px",
  border: 0,
  borderTop: "1px solid #e9edef",
  background: "#ffffff",
  color: "#0a7cff",
  fontSize: 14,
  fontWeight: 600,
  cursor: "pointer",
};

const linkButton = {
  marginTop: 16,
  background: "none",
  border: 0,
  color: "#2c6ecb",
  fontWeight: 600,
  fontSize: 13,
  textDecoration: "underline",
  cursor: "pointer",
};

const WhatsappCodVerificationPreview = ({ autoVerify, showCancelButton }) => {
  // "message" is where every customer starts; opening the link is what moves
  // them on, so the switches only take effect from that point.
  const [step, setStep] = useState("message");

  useEffect(() => {
    setStep("message");
  }, [autoVerify, showCancelButton]);

  const openLink = () => setStep(autoVerify ? "confirmed" : "verify");
  const restart = () => setStep("message");

  if (step === "message") {
    return (
      <div
        style={{
          background: CHAT_PAPER,
          border: "1px solid #e1e3e5",
          borderRadius: 12,
          padding: 14,
        }}
      >
        <div
          style={{
            background: "#ffffff",
            borderRadius: 10,
            boxShadow: "0 1px 2px rgba(0,0,0,0.12)",
            overflow: "hidden",
            maxWidth: 300,
          }}
        >
          <div style={{ padding: "10px 12px", fontSize: 13.5, color: "#111b21" }}>
            <div style={{ fontWeight: 700, marginBottom: 6 }}>
              {I18n.t("whatsapp_cod_verification_preview.confirm_your_cod_order")}
            </div>
            <div style={{ lineHeight: 1.5, whiteSpace: "pre-wrap" }}>
              {`Hi ${DEMO.customer},

Your order placed on ${DEMO.storeName} 📦 needs a quick confirmation before we ship it.

Order ID - ${DEMO.orderNumber}
Total amount - ${DEMO.amount}

Tap below to confirm your order.`}
            </div>
            <div
              style={{
                marginTop: 6,
                fontSize: 10,
                color: "#667781",
                textAlign: "right",
              }}
            >
              10:46
            </div>
          </div>

          {/* The link flow this page controls sends one button, which opens
              the verification page. Confirm and Cancel live on that page, not
              in the message: Show cancel button is link-flow only. */}
          <button type="button" onClick={openLink} style={quickReply}>
            {I18n.t("whatsapp_cod_verification_preview.confirm_your_order")}
          </button>
        </div>

        <div style={{ fontSize: 11, color: "#6d7175", marginTop: 10 }}>
          {showCancelButton
            ? "Tap to open the verification page, where Confirm and Cancel are."
            : "Tap to open the verification page, where Confirm is."}
        </div>
      </div>
    );
  }

  const shell = {
    border: "1px solid #e1e3e5",
    borderRadius: 12,
    background: "#ffffff",
    overflow: "hidden",
  };

  return (
    <div style={shell}>
      <div
        style={{
          padding: "14px 18px",
          borderBottom: "1px solid #e1e3e5",
          background: "#fafbfb",
        }}
      >
        <div style={{ fontSize: 12, color: "#6d7175" }}>{DEMO.storeName}</div>
        <div style={{ fontSize: 15, fontWeight: 650, color: "#202223" }}>
          {t("order_verify_title", "Confirm your order")}
        </div>
        <div style={{ fontSize: 12, color: "#6d7175", marginTop: 4 }}>
          #{DEMO.orderNumber} · {DEMO.customer}
        </div>
      </div>

      {step === "confirmed" && (
        <Outcome
          tone="ok"
          title={t("order_confirmed_title", "Order confirmed")}
          message={
            autoVerify
              ? "Auto verify confirmed the order as the link opened, so the customer never saw the buttons."
              : t(
                  "order_confirmed_message",
                  "Your order has been verified successfully!"
                )
          }
          onRestart={restart}
        />
      )}

      {step === "cancelled" && (
        <Outcome
          tone="bad"
          title={t("order_cancelled_title", "Order cancelled")}
          message={t(
            "order_cancelled_message",
            "Your order has been cancelled. If this was a mistake, please place a new order."
          )}
          onRestart={restart}
        />
      )}

      {step === "verify" && (
        <div style={{ padding: "18px" }}>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              fontSize: 13,
              color: "#202223",
              paddingBottom: 12,
              borderBottom: "1px solid #f1f2f3",
            }}
          >
            <span>{I18n.t("whatsapp_cod_verification_preview.order_total")}</span>
            <strong>{DEMO.amount}</strong>
          </div>

          <div style={{ fontSize: 12, color: "#6d7175", margin: "12px 0 14px" }}>
            {I18n.t("whatsapp_cod_verification_preview.confirm_so_we_can_pack_and")}
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <button
              type="button"
              onClick={() => setStep("confirmed")}
              style={{
                width: "100%",
                padding: "10px 14px",
                borderRadius: 8,
                border: 0,
                background: "#202223",
                color: "#ffffff",
                fontWeight: 650,
                fontSize: 14,
                cursor: "pointer",
              }}
            >
              {t("confirm_order", "Confirm order")}
            </button>

            {showCancelButton && (
              <button
                type="button"
                onClick={() => setStep("cancelled")}
                style={{
                  width: "100%",
                  padding: "10px 14px",
                  borderRadius: 8,
                  border: "1px solid #c9cccf",
                  background: "#ffffff",
                  color: "#202223",
                  fontWeight: 600,
                  fontSize: 14,
                  cursor: "pointer",
                }}
              >
                {t("cancel_order", "Cancel order")}
              </button>
            )}
          </div>

          <button type="button" onClick={restart} style={linkButton}>
            {I18n.t("whatsapp_cod_verification_preview.back_to_the_message")}
          </button>
        </div>
      )}
    </div>
  );
};

export default WhatsappCodVerificationPreview;
