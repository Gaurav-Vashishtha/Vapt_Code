import React from "react";
import { Card, BlockStack, InlineStack, Text, Badge, Button, Banner } from "@shopify/polaris";
import { t } from "../i18n";
import EmbedTutorial from "../components/EmbedTutorial";

/**
 * Status of the NEW "COD Form" app embed with a deep link to the theme
 * editor, and the product-decision warning about the older embed (Q3).
 * External pages open in a new tab (H.7).
 */
const EmbedStatusCard = ({ embed, showLegacyWarning, refreshing, onRefresh }) => {
  const info = embed || {};
  // `enabled: null` means the theme could not be read: neutral, not "off".
  const unknown = info.enabled === null || info.enabled === undefined;
  const legacyUrl = info.legacy_theme_editor_url || info.theme_editor_url;
  return (
    <BlockStack gap="400">
      {showLegacyWarning && (
        <Banner
          tone="info"
          title={t("setup.legacy_embed_title", "Express checkout is also on")}
          action={
            legacyUrl
              ? { content: t("setup.legacy_embed_cta", "Open theme editor"), url: legacyUrl, external: true, target: "_blank" }
              : undefined
          }
        >
          <p>
            {t(
              "setup.legacy_embed_body",
              "Both can run together. While \"COD King OTP Block\" is on, your theme's Buy now and Checkout buttons open Express checkout, and the Buy with COD button opens the COD Form. Turn that embed off only if you want those buttons to go to Shopify checkout.",
            )}
          </p>
        </Banner>
      )}
      <Card>
        <BlockStack gap="300">
          <InlineStack align="space-between" blockAlign="center" gap="300">
            <InlineStack gap="200" blockAlign="center">
              <Text as="h2" variant="headingMd">
                {t("setup.embed_title", "App embed")}
              </Text>
              {unknown ? (
                <Badge>{t("setup.embed_unknown", "Not checked")}</Badge>
              ) : info.enabled ? (
                <Badge tone="success">{t("setup.embed_on", "On in your theme")}</Badge>
              ) : (
                <Badge tone="critical">{t("setup.embed_off", "Off in your theme")}</Badge>
              )}
            </InlineStack>
            <InlineStack gap="200">
              <Button onClick={onRefresh} loading={refreshing}>
                {t("setup.embed_refresh", "Check again")}
              </Button>
              <Button
                variant={info.enabled ? "secondary" : "primary"}
                url={info.theme_editor_url || undefined}
                external
                target="_blank"
                disabled={!info.theme_editor_url}
              >
                {t("setup.embed_open_editor", "Open theme editor")}
              </Button>
            </InlineStack>
          </InlineStack>
          <Text as="p" variant="bodyMd" tone="subdued">
            {unknown
              ? t("setup.embed_unknown_body", "Your theme could not be read just now. Check again in a moment.")
              : info.enabled
              ? t("setup.embed_on_body", "The \"COD Form\" app embed is on. It adds the COD button and loads the form only when a buyer asks for it.")
              : t("setup.embed_off_body", "Turn on the \"COD Form\" app embed in the theme editor, save the theme, then come back and check again. The editor opens in a new tab.")}
          </Text>
          {info.enabled === false && <EmbedTutorial />}
        </BlockStack>
      </Card>
    </BlockStack>
  );
};

export default EmbedStatusCard;
