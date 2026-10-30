import React from "react";
import { Banner, BlockStack, Text, Link } from "@shopify/polaris";
import translateWhatsappError from "../utils/whatsappErrorMessages";

// Renders a critical Polaris Banner with a translated title + body + optional
// action link. Pass either the raw Meta error string (e.g. the full
// `error_message` column) or an explicit `code` + `rawMessage`. Falls back to
// the raw message when we don't have a translation for the code.
const WhatsappErrorBanner = ({ code, rawMessage, onDismiss }) => {
  if (!code && !rawMessage) return null;
  const { title, body, actionLabel, actionHref } = translateWhatsappError({
    code,
    rawMessage,
  });
  return (
    <Banner tone="critical" title={title} onDismiss={onDismiss}>
      <BlockStack gap="200">
        <Text as="p">{body}</Text>
        {actionLabel && actionHref && (
          <Link
            url={actionHref}
            external={actionHref.startsWith("http")}
            removeUnderline={false}
          >
            {actionLabel}
          </Link>
        )}
      </BlockStack>
    </Banner>
  );
};

export default WhatsappErrorBanner;
