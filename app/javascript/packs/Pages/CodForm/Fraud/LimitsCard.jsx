import React from "react";
import { BlockStack, Checkbox, InlineGrid, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import Gate from "../components/Gate";
import { FEATURES } from "../constants";
import { toInt } from "../utils";
import { t } from "../i18n";

/** Order limits per phone, email and IP within a time window (FRD-2). Off until switched on. */
const LimitsCard = ({ fraud, onChange }) => {
  const limits = fraud.limits || {};
  const rows = [
    { key: "phone", label: t("fraud.limit_phone", "Limit orders per phone number") },
    { key: "email", label: t("fraud.limit_email", "Limit orders per email") },
    { key: "ip", label: t("fraud.limit_ip", "Limit orders per IP address") },
  ];
  return (
    <SectionCard
      title={t("fraud.limits_title", "Order limits")}
      description={t("fraud.limits_help", "Stop repeat fake orders: at most a set number of orders in a set number of hours.")}
    >
      <Gate feature={FEATURES.VELOCITY_LIMITS} compact title={t("fraud.limits_title", "Order limits")}>
        <BlockStack gap="400">
          {rows.map((row) => {
            const limit = limits[row.key] || {};
            return (
              <BlockStack key={row.key} gap="200">
                <Checkbox
                  label={row.label}
                  checked={!!limit.enabled}
                  onChange={(value) => onChange(["fraud", "limits", row.key, "enabled"], value)}
                />
                {limit.enabled && (
                  <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                    <TextField
                      label={t("fraud.limit_orders", "Maximum orders")}
                      type="number"
                      min={1}
                      max={100}
                      value={String(limit.max_orders == null ? "" : limit.max_orders)}
                      onChange={(value) => onChange(["fraud", "limits", row.key, "max_orders"], Math.max(1, toInt(value, 1)))}
                      autoComplete="off"
                    />
                    <TextField
                      label={t("fraud.limit_hours", "Within (hours)")}
                      type="number"
                      min={1}
                      max={720}
                      value={String(limit.window_hours == null ? "" : limit.window_hours)}
                      onChange={(value) => onChange(["fraud", "limits", row.key, "window_hours"], Math.min(720, Math.max(1, toInt(value, 24))))}
                      autoComplete="off"
                    />
                  </InlineGrid>
                )}
              </BlockStack>
            );
          })}
          <TextField
            label={t("fraud.limit_message", "Message when a limit is reached")}
            value={fraud.limit_message || ""}
            onChange={(value) => onChange(["fraud", "limit_message"], value)}
            helpText={t("fraud.blocked_message_help", "Leave empty to use the default text of the form.")}
            maxLength={300}
            autoComplete="off"
          />
        </BlockStack>
      </Gate>
    </SectionCard>
  );
};

export default LimitsCard;
