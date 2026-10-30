import React, { useState } from "react";
import { Banner, BlockStack, Checkbox, Modal, Text } from "@shopify/polaris";
import { t } from "./copy";

export const GUARDRAIL_REASONS = ["quality_low", "failure_spike", "account_blocked"];
const LOW_QUALITY = ["RED", "LOW"];
const WARNING_QUALITY = ["YELLOW", "MEDIUM"];
const FINISHED = ["completed", "cancelled", "failed"];

const quality = (c) => String(c?.account_quality_rating || "").toUpperCase();
export const qualityLow = (c) => LOW_QUALITY.includes(quality(c));
export const qualityWarning = (c) => WARNING_QUALITY.includes(quality(c));

export const isGuardrailPause = (c) => c?.status === "paused" && GUARDRAIL_REASONS.includes(c?.pause_reason);
export const isQuietHoursHold = (c) =>
  ["scheduled", "retry_waiting"].includes(c?.status) && c?.pause_reason === "quiet_hours";

export const needsResumeConfirm = (c) => isGuardrailPause(c) || (c?.status === "paused" && qualityLow(c));

// The server only returns a message string through api.js, so the low-quality
// refusal on launch/resume is recognised by its wording.
export const isQualityLowError = (e) => /number quality is low/i.test(String(e?.message || e || ""));

export const frequencyCapHours = (c) => c?.send_policy?.frequency_cap?.hours || 48;

const pauseTitle = (reason) =>
  ({
    quality_low: t("guardrail_title_quality_low", "Paused automatically: number quality low"),
    failure_spike: t("guardrail_title_failure_spike", "Paused automatically: too many messages blocked"),
    account_blocked: t("guardrail_title_account_blocked", "Paused automatically: WhatsApp blocked sending"),
  })[reason];

const pauseBody = (reason) =>
  ({
    quality_low: t(
      "guardrail_body_quality_low",
      "WhatsApp rated your number quality as low. Sending more now could get your number restricted. Wait for the quality to improve before you resume."
    ),
    failure_spike: t(
      "guardrail_body_failure_spike",
      "WhatsApp blocked many of this campaign's messages in the last 30 minutes for sending too fast or too often. Wait a few hours before you resume."
    ),
    account_blocked: t(
      "guardrail_body_account_blocked",
      "WhatsApp stopped messages from your number. This usually means the account is locked, has a payment problem or needs to be registered again. Fix it in Meta Business Manager, then resume."
    ),
  })[reason];

export const statusSubLabel = (c) => {
  if (isGuardrailPause(c)) return pauseTitle(c.pause_reason);
  if (isQuietHoursHold(c)) {
    return c.scheduled_at_display
      ? t("held_quiet_hours_at", "Held for quiet hours — resumes %{time}", { time: c.scheduled_at_display })
      : t("held_quiet_hours", "Held for quiet hours — resumes at %{time}", { time: c?.quiet_hours?.end || "9:00 AM" });
  }
  return null;
};

const GuardrailBanner = ({ campaign, onResume, named = false }) => {
  if (!campaign) return null;

  if (isGuardrailPause(campaign)) {
    return (
      <Banner
        tone="critical"
        title={named ? `${campaign.name}: ${pauseTitle(campaign.pause_reason)}` : pauseTitle(campaign.pause_reason)}
        action={onResume ? { content: t("guardrail_resume", "Resume campaign"), onAction: onResume } : undefined}
      >
        <BlockStack gap="100">
          <Text as="p">{pauseBody(campaign.pause_reason)}</Text>
          {campaign.paused_at_display && (
            <Text as="p" variant="bodySm" tone="subdued">
              {t("guardrail_paused_at", "Paused %{time}. Nobody who already got the message will get it again.", {
                time: campaign.paused_at_display,
              })}
            </Text>
          )}
        </BlockStack>
      </Banner>
    );
  }

  if (isQuietHoursHold(campaign)) {
    return (
      <Banner tone="info" title={statusSubLabel(campaign)}>
        <Text as="p">
          {t("held_quiet_hours_body", "This campaign doesn't send between %{start} and %{end} in your store's time, so customers aren't messaged at night.", {
            start: campaign.quiet_hours?.start || "9:00 PM",
            end: campaign.quiet_hours?.end || "9:00 AM",
          })}
        </Text>
      </Banner>
    );
  }

  if (FINISHED.includes(campaign.status) || campaign.status === "draft") return null;

  if (qualityLow(campaign)) {
    return (
      <Banner tone="critical" title={t("quality_low_title", "Your number quality is low")}>
        <Text as="p">
          {t("quality_low_body", "Sending more marketing messages now could get your number restricted. Keep messages relevant and only send to customers who expect them.")}
        </Text>
      </Banner>
    );
  }

  if (qualityWarning(campaign)) {
    return (
      <Banner tone="warning" title={t("quality_warning_title", "Your number quality is medium")}>
        <Text as="p">
          {t("quality_warning_body", "Your number quality is medium. Keep messages relevant to avoid restrictions.")}
        </Text>
      </Banner>
    );
  }

  return null;
};

const riskBody = (campaign, launching) => {
  if (!launching && isGuardrailPause(campaign)) return pauseBody(campaign.pause_reason);
  return t(
    "risk_body_quality_low",
    "WhatsApp rated your number quality as low. Sending now could get your number restricted, and you may not be able to message customers at all for a while."
  );
};

export const RiskConfirmModal = ({ campaign, launching = false, loading = false, onClose, onConfirm }) => {
  const [understood, setUnderstood] = useState(false);
  return (
    <Modal
      open
      onClose={onClose}
      title={
        launching
          ? t("risk_title_send", "Send while your number quality is low?")
          : t("risk_title_resume", "Resume \"%{name}\"?", { name: campaign?.name || "" })
      }
      primaryAction={{
        content: launching ? t("risk_send", "Send anyway") : t("guardrail_resume", "Resume campaign"),
        destructive: true,
        disabled: !understood,
        loading,
        onAction: onConfirm,
      }}
      secondaryActions={[{ content: t("keep_paused", "Not now"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="300">
          <Text as="p">{riskBody(campaign, launching)}</Text>
          <Checkbox label={t("risk_understand", "I understand the risk")} checked={understood} onChange={setUnderstood} />
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

export default GuardrailBanner;
