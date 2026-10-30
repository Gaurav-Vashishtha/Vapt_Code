import React from "react";
import { Icon, Tooltip } from "@shopify/polaris";
import { ClockMinor, TickSmallMinor, CircleAlertMajor } from "@shopify/polaris-icons";
import { t } from "./format";

const wrap = { display: "inline-flex", alignItems: "center", lineHeight: 0 };
const tick = { display: "inline-flex", width: 14, overflow: "hidden", justifyContent: "flex-start" };

const DoubleTick = ({ tone, label }) => (
  <span style={wrap} aria-label={label} role="img">
    <span style={tick}>
      <Icon source={TickSmallMinor} tone={tone} />
    </span>
    <span style={{ ...tick, marginInlineStart: -6 }}>
      <Icon source={TickSmallMinor} tone={tone} />
    </span>
  </span>
);

const DeliveryTicks = ({ status, error }) => {
  if (!status) return null;
  let label;
  let mark;
  switch (status) {
    case "queued":
      label = t("ticks.queued", "Sending");
      mark = <Icon source={ClockMinor} tone="subdued" accessibilityLabel={label} />;
      break;
    case "sent":
      label = t("ticks.sent", "Sent");
      mark = <Icon source={TickSmallMinor} tone="subdued" accessibilityLabel={label} />;
      break;
    case "delivered":
      label = t("ticks.delivered", "Delivered");
      mark = <DoubleTick tone="subdued" label={label} />;
      break;
    case "read":
      label = t("ticks.read", "Read");
      mark = <DoubleTick tone="interactive" label={label} />;
      break;
    case "failed": {
      const reason = error?.message || t("ticks.failed", "Not delivered");
      label = error?.code ? `${reason} (${error.code})` : reason;
      mark = <Icon source={CircleAlertMajor} tone="critical" accessibilityLabel={label} />;
      break;
    }
    default:
      return null;
  }
  return (
    <Tooltip content={label}>
      <span style={wrap}>{mark}</span>
    </Tooltip>
  );
};

export default DeliveryTicks;
