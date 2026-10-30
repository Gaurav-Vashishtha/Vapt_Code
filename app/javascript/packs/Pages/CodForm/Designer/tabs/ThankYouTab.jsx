import React from "react";
import { BlockStack, Card, ChoiceList, Text, TextField } from "@shopify/polaris";
import { LIMITS, localeName } from "../../constants";
import { t } from "../../i18n";

const VARIABLES = "{order_name} {order_number} {order_id} {total} {first_name} {last_name} {phone} {email}";

/** Thank-you options (TY-1): order status page, custom URL, in-form message, WhatsApp. */
const ThankYouTab = ({ config, setConfig, locale }) => {
  const thankYou = config.thank_you || {};
  const whatsapp = thankYou.whatsapp || {};
  const type = thankYou.type || "order_status";
  const set = (patch) => setConfig((current) => ({ ...current, thank_you: { ...(current.thank_you || {}), ...patch } }));
  const setLocalized = (map, value) => {
    const next = { ...(map || {}) };
    if (value === "" && locale !== "en") delete next[locale];
    else next[locale] = value;
    return next;
  };
  const urlInvalid = type === "custom_url" && !/^https:\/\//i.test(thankYou.url || "");
  const phoneInvalid = type === "whatsapp" && !/^\+?\d{7,15}$/.test(String(whatsapp.phone || "").replace(/[\s-]/g, ""));

  return (
    <BlockStack gap="400">
      <Card>
        <BlockStack gap="400">
          <ChoiceList
            title={t("designer.thank_you_type", "After the order is placed")}
            choices={[
              {
                label: t("designer.thank_you_order_status", "Shopify order status page"),
                value: "order_status",
                helpText: t("designer.thank_you_order_status_help", "The default. If the order has no status page, the message below is shown instead."),
              },
              { label: t("designer.thank_you_custom_url", "Redirect to a custom URL"), value: "custom_url" },
              {
                label: t("designer.thank_you_message", "Stay on the page and show the order details in the form (no redirect)"),
                value: "message",
                helpText: t("designer.thank_you_message_help", "The buyer sees your message, the items, the total and the delivery address in the popup."),
              },
              { label: t("designer.thank_you_whatsapp", "Open WhatsApp with a prefilled message"), value: "whatsapp" },
            ]}
            selected={[type]}
            onChange={(value) => set({ type: value[0] })}
          />

          {type === "custom_url" && (
            <TextField
              label={t("designer.thank_you_url", "URL")}
              value={thankYou.url || ""}
              onChange={(value) => set({ url: value.trim() })}
              placeholder="https://your-store.com/pages/thank-you?order={order_name}"
              error={urlInvalid ? t("designer.https_required", "Use a link that starts with https://") : undefined}
              autoComplete="off"
            />
          )}

          {(type === "message" || type === "order_status") && (
            <TextField
              label={t("designer.thank_you_message_label", "Message (%{language})", { language: localeName(locale) })}
              value={(thankYou.message && thankYou.message[locale]) || ""}
              placeholder={(thankYou.message && thankYou.message.en) || ""}
              onChange={(value) => set({ message: setLocalized(thankYou.message, value) })}
              multiline={3}
              maxLength={LIMITS.TEXT_MAX_CHARS}
              showCharacterCount
              autoComplete="off"
            />
          )}

          {type === "whatsapp" && (
            <>
              <TextField
                label={t("designer.thank_you_whatsapp_phone", "Your WhatsApp number, with country code")}
                value={whatsapp.phone || ""}
                onChange={(value) => set({ whatsapp: { ...whatsapp, phone: value.trim() } })}
                placeholder="+36301234567"
                error={phoneInvalid ? t("designer.thank_you_whatsapp_phone_error", "Enter the number with its country code, digits only.") : undefined}
                autoComplete="off"
              />
              <TextField
                label={t("designer.thank_you_whatsapp_message", "Prefilled message (%{language})", { language: localeName(locale) })}
                value={(whatsapp.message && whatsapp.message[locale]) || ""}
                placeholder={(whatsapp.message && whatsapp.message.en) || ""}
                onChange={(value) => set({ whatsapp: { ...whatsapp, message: setLocalized(whatsapp.message, value) } })}
                multiline={2}
                maxLength={LIMITS.TEXT_MAX_CHARS}
                autoComplete="off"
              />
            </>
          )}

          <Text as="p" variant="bodySm" tone="subdued">
            {t("designer.thank_you_variables", "Variables you can use: %{variables}", { variables: VARIABLES })}
          </Text>
        </BlockStack>
      </Card>
    </BlockStack>
  );
};

export default ThankYouTab;
