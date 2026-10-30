import React from "react";
import { BlockStack, Checkbox, ChoiceList, InlineStack, Select, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import { useGate, UpgradeCard } from "../components/Gate";
import { FEATURES } from "../constants";
import { t } from "../i18n";

/**
 * OTP in the form (OTP-1, OTP-6, OTP-7): on / off for the form and when to ask for the code.
 * The form's switch is its own (`otp.enabled`, off until turned on); it does not follow the
 * store-wide pre-order OTP switch. The channel, the number of codes and the resend wait are
 * the form's own settings too; nothing here is read from the OTP verification screen.
 */
const OtpModeCard = ({ otp, onChange, title }) => {
  const riskGate = useGate(FEATURES.RISK_BASED_OTP);
  const mode = otp.mode || "before_order";
  const enabled = otp.enabled === true;
  return (
    <SectionCard
      title={title || t("fraud.otp_mode_title", "OTP in the form")}
      description={t("fraud.otp_mode_help", "Verify the buyer's phone number with a one-time code.")}
    >
      <BlockStack gap="400">
        <Checkbox
          label={t("fraud.otp_enable", "Ask buyers to verify their phone number with a code")}
          helpText={t("fraud.otp_enable_help", "Applies to the COD Form only. Your other COD King checkout settings are not changed.")}
          checked={enabled}
          onChange={(value) => onChange(["otp", "enabled"], value)}
        />
        <Checkbox
          label={t("fraud.otp_whatsapp", "Let buyers get the code on WhatsApp")}
          helpText={t("fraud.otp_whatsapp_help", "SMS is always offered. With this on, the buyer can choose WhatsApp instead.")}
          checked={otp.whatsapp === true}
          disabled={!enabled}
          onChange={(value) => onChange(["otp", "whatsapp"], value)}
        />
        <InlineStack gap="400" wrap>
          <div style={{ minWidth: 220 }}>
            <Select
              label={t("fraud.otp_max_attempts", "Codes a buyer can request")}
              options={[1, 2, 3, 4, 5].map((n) => ({ value: String(n), label: String(n) }))}
              value={String(otp.max_attempts || 3)}
              disabled={!enabled}
              onChange={(value) => onChange(["otp", "max_attempts"], Number(value))}
            />
          </div>
          <div style={{ minWidth: 220 }}>
            <TextField
              label={t("fraud.otp_resend_wait", "Wait before resending")}
              type="number"
              min={15}
              max={300}
              suffix={t("fraud.otp_seconds", "seconds")}
              autoComplete="off"
              value={String(otp.resend_wait_seconds == null ? 30 : otp.resend_wait_seconds)}
              disabled={!enabled}
              onChange={(value) => onChange(["otp", "resend_wait_seconds"], value === "" ? "" : Number(value))}
            />
          </div>
        </InlineStack>
        <ChoiceList
          title={t("fraud.otp_mode_choice", "When to ask for the code")}
          choices={[
            {
              label: t("fraud.otp_before_order", "Before the order is created"),
              value: "before_order",
              helpText: t("fraud.otp_before_order_help", "Recommended. No order exists until the phone number is verified."),
            },
            {
              label: t("fraud.otp_order_first", "Create the order first, then verify"),
              value: "order_first",
              helpText: t("fraud.otp_order_first_help", "The order is created straight away and tagged once the buyer verifies."),
            },
            {
              label: t("fraud.otp_risk_based", "Only for medium-risk buyers"),
              value: "risk_based",
              disabled: !riskGate.allowed,
              helpText: t("fraud.otp_risk_based_help", "Uses COD King's return-risk score. Low-risk buyers skip the code."),
            },
          ]}
          disabled={!enabled}
          selected={[mode === "risk_based" && !riskGate.allowed ? "before_order" : mode]}
          onChange={(value) => onChange(["otp", "mode"], value[0])}
        />
        {!riskGate.allowed && (
          <UpgradeCard compact minTier={riskGate.minTier} title={t("fraud.otp_risk_based", "Only for medium-risk buyers")} />
        )}
        {mode === "risk_based" && riskGate.allowed && (
          <Select
            label={t("fraud.otp_risk_band", "Ask for OTP from this risk level")}
            options={[
              { value: "medium", label: t("fraud.band_medium", "Medium") },
              { value: "high", label: t("fraud.band_high", "High") },
            ]}
            value={otp.risk_band || "medium"}
            onChange={(value) => onChange(["otp", "risk_band"], value)}
          />
        )}
      </BlockStack>
    </SectionCard>
  );
};

export default OtpModeCard;
