import React from "react";
import { Badge, BlockStack, Box, InlineStack, Link, Text } from "@shopify/polaris";
import DeliveryTicks from "./DeliveryTicks";
import MessageMedia from "./MessageMedia";
import { safeExternalUrl, t, timeOfDay } from "./format";

const MEDIA_KINDS = ["image", "video", "audio", "document", "sticker", "location", "contacts"];
const textStyle = { whiteSpace: "pre-wrap", overflowWrap: "anywhere" };

const sourceCaption = (message) => {
  const ctx = message.context || {};
  const content = message.content || {};
  const templateName = ctx.template_name || content.template_name;
  switch (message.source) {
    case "campaign":
      return t("thread.campaign_from", "Campaign · %{name}", { name: ctx.campaign_name || templateName || "—" });
    case "notification":
      return t("thread.notification_from", "Notification · %{name}", { name: ctx.event_label || templateName || "—" });
    case "auto_reply":
      return t("thread.auto_reply", "Auto-reply");
    case "ai":
      return t("thread.ai_reply", "AI assistant");
    case "payment_link":
      return t("thread.payment_link", "Payment link");
    default:
      return message.kind === "template" && templateName
        ? t("thread.template_from", "Template · %{name}", { name: templateName })
        : null;
  }
};

const Body = ({ message, onOpenImage }) => {
  const { kind, body, content } = message;
  if (kind === "button" || kind === "interactive") {
    return (
      <BlockStack gap="100">
        <Text as="span" variant="bodySm" tone="subdued">
          {t("thread.button_tap", "Tapped a button")}
        </Text>
        <div>
          <Badge tone="info">{body || content?.button_text || content?.payload || "—"}</Badge>
        </div>
      </BlockStack>
    );
  }
  if (kind === "unsupported") {
    return (
      <Text as="span" tone="subdued">
        {t("thread.unsupported", "This message type can't be shown here. Check WhatsApp on your phone to see it.")}
      </Text>
    );
  }
  if (kind === "order") {
    return <Text as="span">{body || t("thread.order", "Sent a cart from your WhatsApp catalog")}</Text>;
  }
  if (kind === "reaction") {
    return (
      <Text as="span">
        {content?.emoji
          ? t("thread.reaction", "Reacted %{emoji}", { emoji: content.emoji })
          : t("thread.reaction_removed", "Removed a reaction")}
      </Text>
    );
  }
  const media = MEDIA_KINDS.includes(kind);
  return (
    <BlockStack gap="150">
      {media && <MessageMedia message={message} onOpenImage={onOpenImage} />}
      {body && (
        <Text as="p" variant="bodyMd">
          <span style={textStyle}>{body}</span>
        </Text>
      )}
    </BlockStack>
  );
};

const MessageBubble = ({ message, reactions = [], onOpenImage }) => {
  if (message.kind === "system") {
    return (
      <Box paddingBlock="100">
        <Text as="p" variant="bodySm" tone="subdued" alignment="center">
          {message.body || t("thread.system", "WhatsApp update")}
        </Text>
      </Box>
    );
  }

  const outbound = message.direction === "outbound";
  const caption = sourceCaption(message);
  const referral = message.content?.referral;
  const failed = message.status === "failed";

  return (
    <div style={{ display: "flex", justifyContent: outbound ? "flex-end" : "flex-start" }}>
      <div style={{ maxWidth: "78%", minWidth: 0 }}>
        <Box
          padding="200"
          paddingInline="300"
          borderRadius="300"
          background={outbound ? (failed ? "bg-surface-critical" : "bg-surface-success") : "bg-surface-secondary"}
        >
          <BlockStack gap="100">
            {caption && (
              <Text as="span" variant="bodySm" tone="subdued" fontWeight="medium">
                {caption}
              </Text>
            )}
            {referral && (
              <Text as="span" variant="bodySm" tone="subdued">
                {safeExternalUrl(referral.source_url) ? (
                  <Link url={safeExternalUrl(referral.source_url)} external>
                    {t("thread.from_ad", "From ad: %{headline}", { headline: referral.headline || referral.source_url })}
                  </Link>
                ) : (
                  t("thread.from_ad", "From ad: %{headline}", { headline: referral.headline || "—" })
                )}
              </Text>
            )}
            {message.reply_to && (
              <Box padding="150" background="bg-surface" borderRadius="200" borderInlineStartWidth="050" borderColor="border-emphasis">
                <Text as="span" variant="bodySm" tone="subdued" truncate>
                  {message.reply_to.preview || "—"}
                </Text>
              </Box>
            )}
            <Body message={message} onOpenImage={onOpenImage} />
            {failed && (
              <Text as="span" variant="bodySm" tone="critical">
                {message.error?.message
                  ? t("thread.failed_with_reason", "Not delivered: %{reason}", { reason: message.error.message })
                  : t("ticks.failed", "Not delivered")}
                {message.error?.code ? ` (${message.error.code})` : ""}
              </Text>
            )}
            <InlineStack gap="100" align="end" blockAlign="center" wrap={false}>
              {outbound && message.agent?.name && (
                <Text as="span" variant="bodySm" tone="subdued" truncate>
                  {message.agent.name}
                </Text>
              )}
              <Text as="span" variant="bodySm" tone="subdued">
                {timeOfDay(message.occurred_at)}
              </Text>
              {outbound && <DeliveryTicks status={message.status} error={message.error} />}
            </InlineStack>
          </BlockStack>
        </Box>
        {reactions.length > 0 && (
          <div style={{ display: "flex", justifyContent: outbound ? "flex-end" : "flex-start", marginTop: -6, paddingInline: 8 }}>
            <Box paddingInline="150" background="bg-surface" borderRadius="full" borderWidth="025" borderColor="border">
              <span aria-label={t("thread.reactions", "Reactions")}>{reactions.join(" ")}</span>
            </Box>
          </div>
        )}
      </div>
    </div>
  );
};

export default MessageBubble;
