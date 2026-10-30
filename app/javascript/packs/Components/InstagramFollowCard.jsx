import React, { useState } from "react";
import { Box, BlockStack, InlineStack, Text, Button, Card } from "@shopify/polaris";
import I18n from "../i18n-lang";

const INSTAGRAM_URL = "https://www.instagram.com/codkingshopify/";
// The Instagram glyph, loaded from the Simple Icons CDN (brand pink). If it cannot load, the
// card shows without a logo.
const LOGO_SRC = "https://cdn.simpleicons.org/instagram/E4405F";
const DISMISS_KEY = "cod_king_instagram_card_dismissed_v1";

const wasDismissed = () => {
  try {
    return window.localStorage.getItem(DISMISS_KEY) === "1";
  } catch (error) {
    return false;
  }
};

/** Summary page: invites every merchant to follow COD King on Instagram. */
const InstagramFollowCard = () => {
  const [dismissed, setDismissed] = useState(wasDismissed);
  const [logoOk, setLogoOk] = useState(true);
  if (dismissed) return null;

  const dismiss = () => {
    setDismissed(true);
    try {
      window.localStorage.setItem(DISMISS_KEY, "1");
    } catch (error) {
      /* the card simply comes back on the next visit */
    }
  };

  return (
    <Box paddingBlockEnd="500">
      <Card padding="0">
        <Box paddingBlock="300" paddingInline="400">
          <InlineStack align="space-between" blockAlign="center" gap="300" wrap={false}>
            <InlineStack gap="300" blockAlign="center" wrap={false}>
            {logoOk && (
              <img
                src={LOGO_SRC}
                alt="Instagram"
                width="28"
                height="28"
                style={{ display: "block", flex: "0 0 auto" }}
                onError={() => setLogoOk(false)}
              />
            )}
            <BlockStack gap="050">
              <Text variant="headingSm" as="h3">
                {I18n.t("summary.instagram_title", { defaultValue: "Follow COD King on Instagram" })}
              </Text>
              <Text variant="bodySm" as="p" tone="subdued">
                {I18n.t("summary.instagram_body", {
                  defaultValue: "Get the latest updates, new features and tips to grow your COD orders.",
                })}
              </Text>
            </BlockStack>
            </InlineStack>
            <InlineStack gap="200" blockAlign="center" wrap={false}>
              <Button variant="primary" size="slim" url={INSTAGRAM_URL} external target="_blank">
                {I18n.t("summary.instagram_cta", { defaultValue: "Follow @codkingshopify" })}
              </Button>
              <Button
                variant="tertiary"
                size="slim"
                onClick={dismiss}
                accessibilityLabel={I18n.t("summary.instagram_dismiss_label", { defaultValue: "Hide the Instagram card" })}
              >
                {I18n.t("summary.instagram_dismiss", { defaultValue: "Not now" })}
              </Button>
            </InlineStack>
          </InlineStack>
        </Box>
      </Card>
    </Box>
  );
};

export default InstagramFollowCard;
