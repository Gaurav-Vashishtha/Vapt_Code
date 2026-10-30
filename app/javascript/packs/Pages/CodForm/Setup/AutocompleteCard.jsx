import React from "react";
import { BlockStack, Checkbox, Select, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import Gate from "../components/Gate";
import { FEATURES } from "../constants";
import { t } from "../i18n";

/** Address autocomplete (INT-3): Google Places or Ola Maps, with the merchant's own key. */
const AutocompleteCard = ({ general, onChange }) => {
  const autocomplete = general.autocomplete || {};
  const provider = autocomplete.provider === "ola" ? "ola" : "google";
  const keyName = `${provider}_api_key`;

  return (
    <div id="address-autocomplete">
      <SectionCard
        title={t("setup.address_autocomplete_title", "Address autocomplete")}
        description={t("setup.address_autocomplete_help", "Suggest full addresses while the buyer types, so fewer orders come back with a wrong address.")}
      >
        <Gate feature={FEATURES.ADDRESS_AUTOCOMPLETE} compact title={t("setup.address_autocomplete_title", "Address autocomplete")}>
          <BlockStack gap="200">
            <Checkbox
              label={t("setup.autocomplete_enabled", "Suggest addresses while the buyer types")}
              checked={!!autocomplete.enabled}
              onChange={(value) => onChange(["autocomplete", "enabled"], value)}
            />
            <Select
              label={t("setup.autocomplete_provider", "Address provider")}
              options={[
                { label: t("setup.autocomplete_google", "Google Places"), value: "google" },
                { label: t("setup.autocomplete_ola", "Ola Maps Places (India)"), value: "ola" },
              ]}
              value={provider}
              onChange={(value) => onChange(["autocomplete", "provider"], value)}
              disabled={!autocomplete.enabled}
            />
            <TextField
              label={provider === "ola" ? t("setup.autocomplete_ola_key", "Ola Maps API key") : t("setup.autocomplete_key", "Google Maps API key")}
              helpText={
                provider === "ola"
                  ? t("setup.autocomplete_ola_key_help", "Use your own Ola Maps key with the Places APIs enabled, restricted to your store domain. Ola bills you for its use.")
                  : t("setup.autocomplete_key_help", "Use your own key with the Places API enabled and restricted to your store domain. Google bills you for its use.")
              }
              value={autocomplete[keyName] || ""}
              onChange={(value) => onChange(["autocomplete", keyName], value.trim())}
              disabled={!autocomplete.enabled}
              error={
                autocomplete.enabled && !autocomplete[keyName]
                  ? t("setup.autocomplete_key_missing", "Enter an API key or turn autocomplete off.")
                  : undefined
              }
              autoComplete="off"
            />
          </BlockStack>
        </Gate>
      </SectionCard>
    </div>
  );
};

export default AutocompleteCard;
