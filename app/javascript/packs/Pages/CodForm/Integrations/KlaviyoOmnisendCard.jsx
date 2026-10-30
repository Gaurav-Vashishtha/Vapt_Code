import React, { useEffect, useState } from "react";
import { Badge, Banner, BlockStack, Button, Card, Checkbox, InlineStack, Text, TextField } from "@shopify/polaris";
import { codFormApi, parseError } from "../api";
import Gate from "../components/Gate";
import { FEATURES } from "../constants";
import { DEFAULT_CRM_CONFIG } from "../defaults";
import { formatDateTime, mergeDefaults } from "../utils";
import { t } from "../i18n";

const CREDENTIAL_KEY = { klaviyo: "private_api_key", omnisend: "api_key" };

/**
 * Klaviyo / Omnisend (INT-2, ABN-4): events for a form order and an
 * abandoned form. The API key is write-only.
 */
const KlaviyoOmnisendCard = ({ provider, item, onChanged }) => {
  const name = provider === "klaviyo" ? "Klaviyo" : "Omnisend";
  const [apiKey, setApiKey] = useState("");
  const [config, setConfig] = useState(mergeDefaults(DEFAULT_CRM_CONFIG, (item && item.config) || {}));
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState(null);
  const connected = !!item && item.status === "connected";
  const failing = !!item && item.status === "error";

  useEffect(() => {
    setConfig(mergeDefaults(DEFAULT_CRM_CONFIG, (item && item.config) || {}));
  }, [item]);

  const save = () => {
    setBusy("save");
    setError(null);
    const payload = { config };
    if (apiKey.trim()) payload.credentials = { [CREDENTIAL_KEY[provider]]: apiKey.trim() };
    codFormApi.integrations
      .update(provider, payload)
      .then(() => {
        setApiKey("");
        if (window.shopify && window.shopify.toast) window.shopify.toast.show(t("integrations.saved", "Saved"));
        return onChanged && onChanged();
      })
      .catch((err) => setError(parseError(err)))
      .then(() => setBusy(null));
  };

  const disconnect = () => {
    setBusy("disconnect");
    setError(null);
    codFormApi.integrations
      .destroy(provider)
      .then(() => onChanged && onChanged())
      .catch((err) => setError(parseError(err)))
      .then(() => setBusy(null));
  };

  return (
    <Card>
      <BlockStack gap="400">
        <InlineStack gap="200" blockAlign="center">
          <Text as="h3" variant="headingSm">
            {name}
          </Text>
          {connected && <Badge tone="success">{t("integrations.connected_badge", "Connected")}</Badge>}
          {failing && <Badge tone="critical">{t("integrations.error_badge", "Needs attention")}</Badge>}
        </InlineStack>
        <Gate feature={FEATURES.KLAVIYO_OMNISEND} compact title={name}>
          <BlockStack gap="400">
            <Text as="p" tone="subdued">
              {t("integrations.crm_help", "Sends an event to %{name} when a form order is placed and when a form is abandoned, so you can run your own flows.", { name })}
            </Text>
            {failing && item.last_error && (
              <Banner tone="critical">
                <p>{item.last_error}</p>
              </Banner>
            )}
            {error && (
              <Banner tone="critical" onDismiss={() => setError(null)}>
                <p>{t("integrations.save_error", "This could not be saved. Check the key and try again.")}</p>
              </Banner>
            )}
            <TextField
              label={provider === "klaviyo" ? t("integrations.klaviyo_key", "Klaviyo private API key") : t("integrations.omnisend_key", "Omnisend API key")}
              type="password"
              value={apiKey}
              onChange={setApiKey}
              placeholder={connected || failing ? "••••••••" : ""}
              helpText={
                connected || failing
                  ? t("integrations.key_saved_help", "A key is saved. Type a new one only to replace it.")
                  : t("integrations.key_help", "The key is stored securely and never shown again.")
              }
              autoComplete="off"
            />
            <InlineStack gap="400" wrap>
              <Checkbox
                label={t("integrations.event_order", "Order placed")}
                checked={config.events.order !== false}
                onChange={(value) => setConfig((current) => ({ ...current, events: { ...current.events, order: value } }))}
              />
              <Checkbox
                label={t("integrations.event_abandoned", "Form abandoned")}
                checked={config.events.abandoned !== false}
                onChange={(value) => setConfig((current) => ({ ...current, events: { ...current.events, abandoned: value } }))}
              />
            </InlineStack>
            {item && item.last_success_at && (
              <Text as="p" variant="bodySm" tone="subdued">
                {t("integrations.last_success", "Last event sent %{date}", { date: formatDateTime(item.last_success_at) })}
              </Text>
            )}
            <InlineStack gap="200">
              <Button variant="primary" onClick={save} loading={busy === "save"} disabled={!connected && !failing && apiKey.trim() === ""}>
                {connected || failing ? t("common.save", "Save") : t("integrations.connect", "Connect")}
              </Button>
              {(connected || failing) && (
                <Button tone="critical" onClick={disconnect} loading={busy === "disconnect"}>
                  {t("integrations.disconnect", "Disconnect")}
                </Button>
              )}
            </InlineStack>
          </BlockStack>
        </Gate>
      </BlockStack>
    </Card>
  );
};

export default KlaviyoOmnisendCard;
