import React from "react";
import { BlockStack, Checkbox, InlineGrid, Select, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import Gate from "../components/Gate";
import { FEATURES } from "../constants";
import { toInt } from "../utils";
import { t } from "../i18n";

/** RTO gating (RUL-3): for risky buyers full COD is replaced by partial payment or Pay online. */
const RtoGatingCard = ({ rto, onChange }) => (
  <SectionCard
    title={t("fraud.rto_title", "Return-risk gating")}
    description={t("fraud.rto_help", "Remove full COD for buyers who are likely to refuse the parcel. They are offered partial payment (when a rule allows it) or Pay online.")}
  >
    <Gate feature={FEATURES.RTO_GATING} compact title={t("fraud.rto_title", "Return-risk gating")}>
      <BlockStack gap="400">
        <Checkbox
          label={t("fraud.rto_enabled", "Remove full COD for risky buyers")}
          checked={!!rto.gating_enabled}
          onChange={(value) => onChange(["rto", "gating_enabled"], value)}
        />
        {rto.gating_enabled && (
          <>
            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
              <Select
                label={t("fraud.rto_band", "From this risk level")}
                options={[
                  { value: "high", label: t("fraud.band_high", "High") },
                  { value: "medium", label: t("fraud.band_medium_and_high", "Medium and high") },
                ]}
                value={rto.block_band || "high"}
                onChange={(value) => onChange(["rto", "block_band"], value)}
              />
              <TextField
                label={t("fraud.rto_min_score", "Or from this risk score (0–100, optional)")}
                type="number"
                min={0}
                max={100}
                value={rto.min_score == null ? "" : String(rto.min_score)}
                onChange={(value) => {
                  const number = toInt(value);
                  onChange(["rto", "min_score"], number === null ? null : Math.min(100, Math.max(0, number)));
                }}
                autoComplete="off"
              />
            </InlineGrid>
            <TextField
              label={t("fraud.rto_message", "Message for these buyers")}
              value={rto.message || ""}
              onChange={(value) => onChange(["rto", "message"], value)}
              helpText={t("fraud.blocked_message_help", "Leave empty to use the default text of the form.")}
              maxLength={300}
              autoComplete="off"
            />
          </>
        )}
      </BlockStack>
    </Gate>
  </SectionCard>
);

export default RtoGatingCard;
