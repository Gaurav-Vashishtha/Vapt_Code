import React, { useState } from "react";
import I18n from "../i18n-lang";

/**
 * The COD King block as it renders inside Shopify's checkout.
 *
 * Mirrors extensions/codk-checkout-otp/src/Checkout.jsx: the same heading,
 * the same field label for each state, and the same two buttons with the same
 * enable rules. Nothing is sent, so the code is 1234 and no OTP goes out.
 *
 * Everything above the block — contact, delivery, shipping method and the
 * payment picker — is Shopify's own checkout, drawn here so a merchant can
 * see where the block lands in the page rather than judging it floating on
 * its own. Only the block itself responds to clicks.
 */
const COPY = {
  get heading() {
      return I18n.t("plus_checkout_otp_preview.to_verify_your_cod_order_click");
    },
  getOtpOn: (phone) => `Get OTP on ${phone}`,
  getOtp: "Get OTP",
  resend: "Resend OTP",
  verifyOtp: "Verify OTP",
  enterOtp: "Enter OTP received on phone",
  phoneVerified: "Phone Number is Verified",
  proceed: "Phone number verified, Proceed with the order.",
  invalidOtp: "Invalid OTP please try again.",
};

// The placeholder the widget preview already uses, and obviously not a real
// number, which the one before it was not.
const DEMO_PHONE = "9876543210";
const PREVIEW_CODE = "1234";

const ACCENT = "#1e4b47";
const BORDER = "#c9cccf";
const HAIRLINE = "#e1e3e5";
const MUTED = "#6d7175";
const INK = "#303030";

const box = {
  border: `1px solid ${HAIRLINE}`,
  borderRadius: 8,
  padding: "14px 16px",
  background: "#ffffff",
};

const button = (primary, disabled) => ({
  padding: "10px 18px",
  borderRadius: 8,
  fontSize: 14,
  fontWeight: 650,
  cursor: disabled ? "not-allowed" : "pointer",
  opacity: disabled ? 0.45 : 1,
  border: primary ? 0 : `1px solid ${BORDER}`,
  background: primary ? ACCENT : "#ffffff",
  color: primary ? "#ffffff" : "#202223",
});

/** A checkout section heading, the weight Shopify gives them. */
const Heading = ({ children, sub, first }) => (
  <div style={{ margin: first ? "0 0 10px" : "18px 0 10px" }}>
    <div style={{ fontSize: 17, fontWeight: 650, color: "#202223" }}>
      {children}
    </div>
    {sub && (
      <div style={{ fontSize: 13, color: MUTED, marginTop: 2 }}>{sub}</div>
    )}
  </div>
);

/** A filled checkout input: floating label above the value, as Shopify renders it. */
const Field = ({ label, value, trailing, flex }) => (
  <div
    style={{
      flex: flex || "1 1 100%",
      minWidth: 0,
      boxSizing: "border-box",
      border: `1px solid ${BORDER}`,
      borderRadius: 8,
      padding: "7px 12px",
      background: "#ffffff",
      display: "flex",
      alignItems: "center",
      gap: 8,
    }}
  >
    <div style={{ minWidth: 0, flex: 1 }}>
      <div style={{ fontSize: 11, color: MUTED, lineHeight: 1.4 }}>{label}</div>
      <div
        style={{
          fontSize: 13,
          color: INK,
          overflow: "hidden",
          textOverflow: "ellipsis",
          whiteSpace: "nowrap",
        }}
      >
        {value}
      </div>
    </div>
    {trailing}
  </div>
);

const Row = ({ children }) => (
  <div style={{ display: "flex", gap: 8, marginBottom: 8, flexWrap: "wrap" }}>
    {children}
  </div>
);

const Chevron = () => (
  <svg viewBox="0 0 20 20" width="14" height="14" aria-hidden="true">
    <path
      d="M5 8l5 5 5-5"
      fill="none"
      stroke={MUTED}
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
);

const MagnifyingGlass = () => (
  <svg viewBox="0 0 20 20" width="14" height="14" aria-hidden="true">
    <circle cx="9" cy="9" r="5.5" fill="none" stroke={MUTED} strokeWidth="1.8" />
    <path d="M13 13l4 4" stroke={MUTED} strokeWidth="1.8" strokeLinecap="round" />
  </svg>
);

/** A radio row, the way checkout draws shipping methods and billing choices. */
const Choice = ({ selected, title, sub, right, first, last }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 10,
      padding: "12px 14px",
      background: selected ? "#f2f7f6" : "#ffffff",
      border: `1px solid ${selected ? ACCENT : HAIRLINE}`,
      borderTopLeftRadius: first ? 8 : 0,
      borderTopRightRadius: first ? 8 : 0,
      borderBottomLeftRadius: last ? 8 : 0,
      borderBottomRightRadius: last ? 8 : 0,
      marginTop: first ? 0 : -1,
      position: "relative",
      zIndex: selected ? 1 : 0,
    }}
  >
    <span
      style={{
        flex: "0 0 auto",
        width: 16,
        height: 16,
        borderRadius: "50%",
        border: `${selected ? 5 : 1.5}px solid ${selected ? ACCENT : BORDER}`,
        background: "#ffffff",
        boxSizing: "border-box",
      }}
    />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontSize: 13, fontWeight: 650, color: INK }}>{title}</div>
      {sub && <div style={{ fontSize: 12, color: MUTED }}>{sub}</div>}
    </div>
    {right && (
      <div style={{ fontSize: 13, fontWeight: 650, color: INK }}>{right}</div>
    )}
  </div>
);

const Banner = ({ tone, children }) => (
  <div
    style={{
      marginTop: 10,
      padding: "8px 12px",
      borderRadius: 8,
      fontSize: 13,
      background: tone === "ok" ? "#e3f5e9" : "#fdeced",
      color: tone === "ok" ? "#0c5132" : "#8e1f0b",
    }}
  >
    {children}
  </div>
);

const PlusCheckoutOtpPreview = () => {
  const [sent, setSent] = useState(false);
  const [verified, setVerified] = useState(false);
  const [invalid, setInvalid] = useState(false);
  const [otp, setOtp] = useState("");

  const reset = () => {
    setSent(false);
    setVerified(false);
    setInvalid(false);
    setOtp("");
  };

  const onVerify = () => {
    if (otp.replace(/\D/g, "") === PREVIEW_CODE) {
      setVerified(true);
      setInvalid(false);
    } else {
      setInvalid(true);
    }
  };

  const label = verified
    ? COPY.phoneVerified
    : sent
    ? COPY.enterOtp
    : COPY.getOtpOn(DEMO_PHONE);

  return (
    <div
      /* No inner scrollbar. A box that scrolls inside a page that also
         scrolls swallows the wheel whenever the cursor is over it, and the
         merchant ends up looking at the preview parked halfway down with the
         first heading cut off. It runs at its natural height instead. */
      style={{
        background: "#f6f6f7",
        border: `1px solid ${HAIRLINE}`,
        borderRadius: 12,
        padding: 14,
      }}
    >
      {/* Checkout chrome. Inert: the merchant is judging placement, and a
          dead click on a field they cannot fill is worse than no click. */}
      <div style={{ pointerEvents: "none" }}>
        <Heading first>{I18n.t("plus_checkout_otp_preview.contact")}</Heading>
        <Row>
          <Field label={I18n.t("plus_checkout_otp_preview.email")} value="rahul.puri@example.com" />
        </Row>

        <Heading>{I18n.t("plus_checkout_otp_preview.delivery")}</Heading>
        <Row>
          <Field label={I18n.t("plus_checkout_otp_preview.country_region")} value="India" trailing={<Chevron />} />
        </Row>
        <Row>
          <Field label={I18n.t("plus_checkout_otp_preview.first_name")} value="Rahul" flex="1 1 46%" />
          <Field label={I18n.t("plus_checkout_otp_preview.last_name")} value="Puri" flex="1 1 46%" />
        </Row>
        <Row>
          <Field
            label={I18n.t("plus_checkout_otp_preview.address")}
            value="New Gopal Nagar, Near Gopal Mandir"
            trailing={<MagnifyingGlass />}
          />
        </Row>
        <Row>
          <Field label={I18n.t("plus_checkout_otp_preview.city")} value="Bengaluru" flex="1 1 46%" />
          <Field label={I18n.t("plus_checkout_otp_preview.pin_code")} value="560025" flex="1 1 46%" />
        </Row>
        <Row>
          <Field label={I18n.t("plus_checkout_otp_preview.phone")} value={DEMO_PHONE} />
        </Row>

        <Heading>{I18n.t("plus_checkout_otp_preview.shipping_method")}</Heading>
        <div>
          <Choice
            first
            title={I18n.t("plus_checkout_otp_preview.standard_5_7_business_days")}
            right="FREE"
          />
          <Choice
            last
            selected
            title={I18n.t("plus_checkout_otp_preview.cash_on_delivery")}
            sub="Cash on Delivery Charges apply"
            right="₹50.00"
          />
        </div>

        <Heading sub="All transactions are secure and encrypted.">
          {I18n.t("plus_checkout_otp_preview.payment")}
        </Heading>
        <div
          style={{
            ...box,
            border: `2px solid ${ACCENT}`,
            background: "#f2f7f6",
            marginBottom: 12,
          }}
        >
          <strong style={{ fontSize: 14 }}>{I18n.t("plus_checkout_otp_preview.cash_on_delivery_cod")}</strong>
        </div>
      </div>

      {/* The extension itself: the only live part of this preview. */}
      <div style={{ ...box, marginBottom: 12 }}>
        <strong style={{ fontSize: 14 }}>{COPY.heading}</strong>
      </div>

      <div style={{ ...box, padding: 0, border: 0 }}>
        <div
          style={{
            border: `1px solid ${BORDER}`,
            borderRadius: 8,
            padding: "10px 12px",
            background: sent && !verified ? "#ffffff" : "#f6f6f7",
          }}
        >
          <div style={{ fontSize: 12, color: MUTED }}>{label}</div>
          {sent && !verified && (
            <input
              value={otp}
              onChange={(e) => {
                setOtp(e.target.value);
                setInvalid(false);
              }}
              placeholder={PREVIEW_CODE}
              inputMode="numeric"
              style={{
                width: "100%",
                marginTop: 6,
                border: 0,
                outline: "none",
                fontSize: 15,
                letterSpacing: 2,
                background: "transparent",
              }}
            />
          )}
        </div>

        {invalid && !verified && <Banner tone="bad">{COPY.invalidOtp}</Banner>}
        {verified && <Banner tone="ok">{COPY.proceed}</Banner>}

        <div style={{ display: "flex", gap: 10, marginTop: 12 }}>
          <button
            type="button"
            onClick={() => {
              setSent(true);
              setInvalid(false);
            }}
            disabled={verified}
            style={button(true, verified)}
          >
            {sent && !verified ? COPY.resend : COPY.getOtp}
          </button>
          <button
            type="button"
            onClick={onVerify}
            disabled={!sent || verified}
            style={button(false, !sent || verified)}
          >
            {COPY.verifyOtp}
          </button>
        </div>

        <div
          style={{
            marginTop: 12,
            textAlign: "center",
            fontSize: 12,
            color: MUTED,
          }}
        >
          {I18n.t("plus_checkout_otp_preview.powered_by_cod_king")}
        </div>

        {(sent || verified) && (
          <div style={{ textAlign: "center", marginTop: 8 }}>
            <button
              type="button"
              onClick={reset}
              style={{
                background: "none",
                border: 0,
                color: "#2c6ecb",
                fontSize: 12,
                fontWeight: 600,
                textDecoration: "underline",
                cursor: "pointer",
              }}
            >
              {I18n.t("plus_checkout_otp_preview.start_over")}
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default PlusCheckoutOtpPreview;
