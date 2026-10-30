import React, { useState } from "react";
import { Card, BlockStack, InlineStack, Text, Badge, Button, Modal, Banner, List } from "@shopify/polaris";
import { t } from "../i18n";

/**
 * COD Form on/off (DSH-5). Both directions ask for confirmation. Turning it
 * on never changes an Express checkout setting. Turning it on waits for the app
 * embed (`embedOff`); no other health item blocks the switch.
 */
const ModeCard = ({ mode, legacyModeLabel, switching, error, disabled, embedOff, onSwitch }) => {
  const [confirmOpen, setConfirmOpen] = useState(false);
  const isOn = mode === "cod_form";
  // The app embed comes first: the form cannot be turned on while the embed is off in the
  // theme. Turning it off is always allowed.
  const needsEmbed = !isOn && embedOff;
  const legacyName =
    legacyModeLabel === "express"
      ? t("setup.legacy_express", "Express checkout")
      : t("setup.legacy_checkout", "Shopify checkout");

  const confirm = () => {
    Promise.resolve(onSwitch(isOn ? "legacy" : "cod_form")).then(() => setConfirmOpen(false));
  };

  return (
    <Card>
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center" gap="400" wrap={false}>
          <BlockStack gap="100">
            <InlineStack gap="200" blockAlign="center">
              <Text as="h2" variant="headingMd">
                {t("setup.mode_card_title", "COD Form")}
              </Text>
              {isOn ? (
                <Badge tone="success" progress="complete">
                  {t("setup.mode_on", "On")}
                </Badge>
              ) : (
                <Badge tone="attention" progress="incomplete">
                  {t("setup.mode_off", "Off")}
                </Badge>
              )}
            </InlineStack>
            <Text as="p" variant="bodyMd" tone="subdued">
              {isOn
                ? t("setup.mode_on_body", "Buyers who tap the COD button order in the COD Form without leaving the page.")
                : t("setup.mode_off_body", "Your store currently uses %{legacy}. Turn on COD Form to add a Buy with COD button that opens a one-page order form.", { legacy: legacyName })}
            </Text>
          </BlockStack>
          <Button
            variant={isOn ? "secondary" : "primary"}
            onClick={() => setConfirmOpen(true)}
            loading={switching}
            disabled={disabled || needsEmbed}
          >
            {isOn ? t("setup.mode_turn_off", "Turn off") : t("setup.mode_turn_on", "Turn on")}
          </Button>
        </InlineStack>
        {needsEmbed && (
          <Text as="p" variant="bodySm" tone="subdued">
            {t("setup.mode_embed_first", "Turn on the COD Form app embed in your theme first (the card above), then click Check again.")}
          </Text>
        )}
        {disabled && (
          <Text as="p" variant="bodySm" tone="subdued">
            {t("setup.mode_save_first", "Save or discard your changes before switching.")}
          </Text>
        )}
        {error && (
          <Banner tone="critical">
            <p>{t("setup.mode_error", "The mode could not be changed. Try again.")}</p>
          </Banner>
        )}
      </BlockStack>

      <Modal
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        title={
          isOn
            ? t("setup.mode_off_confirm_title", "Turn off COD Form?")
            : t("setup.mode_confirm_title", "Turn on COD Form?")
        }
        primaryAction={{
          content: isOn ? t("setup.mode_off_confirm_cta", "Turn off") : t("setup.mode_confirm_cta", "Turn on COD Form"),
          onAction: confirm,
          loading: switching,
          destructive: isOn,
        }}
        secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: () => setConfirmOpen(false) }]}
      >
        <Modal.Section>
          {isOn ? (
            <Text as="p">
              {t("setup.mode_off_confirm_body", "The Buy with COD button is removed from your storefront and your store goes back to %{legacy}. Your form, buttons, rates and offers are kept.", { legacy: legacyName })}
            </Text>
          ) : (
            <BlockStack gap="300">
              <Text as="p">
                {t("setup.mode_confirm_body", "COD Form adds a Buy with COD button to your storefront. All your Express checkout settings are kept and nothing else changes.")}
              </Text>
              <List type="bullet">
                <List.Item>{t("setup.mode_confirm_point_embed", "The button appears once the COD Form app embed is on in your theme.")}</List.Item>
                <List.Item>{t("setup.mode_confirm_point_fallback", "If the form cannot open, the button takes the buyer to Shopify checkout.")}</List.Item>
                <List.Item>{t("setup.mode_confirm_point_off", "You can turn it off here at any time.")}</List.Item>
              </List>
            </BlockStack>
          )}
        </Modal.Section>
      </Modal>
    </Card>
  );
};

export default ModeCard;
