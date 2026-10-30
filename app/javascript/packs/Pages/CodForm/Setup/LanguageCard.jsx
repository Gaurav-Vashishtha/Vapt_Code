import React from "react";
import { Banner, BlockStack, Select } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import { SHIPPED_LOCALES, localeName } from "../constants";
import { t } from "../i18n";

/**
 * Setup → Form language (general.language). "" = every buyer sees the form, COD button, quantity
 * offers and bundles in the storefront's own language; a code = always in that language. A form
 * can still pick its own language in Designer → Texts, which wins over this one.
 */
const LanguageCard = ({ general, onChange, locales }) => {
  const value = general.language || "";
  const codes = Array.from(new Set([...SHIPPED_LOCALES, ...(locales || []), ...(value ? [value] : [])]));
  const shipped = !value || SHIPPED_LOCALES.includes(value.split("-")[0]);

  return (
    <div id="form-language">
      <SectionCard
        title={t("setup.language_title", "Form language")}
        description={t(
          "setup.language_help",
          "The language of the COD button, the quantity offers, bundles, upsells and the whole order form.",
        )}
      >
        <BlockStack gap="300">
          <Select
            label={t("setup.language_label", "Show the form in")}
            options={[
              { value: "", label: t("setup.language_follow", "Storefront language (default)") },
              ...codes.map((code) => ({ value: code, label: localeName(code) })),
            ]}
            value={value}
            onChange={(next) => onChange(["language"], next)}
            helpText={
              value
                ? t("setup.language_fixed_help", "Every buyer sees the form in this language, whatever language your storefront is in.")
                : t("setup.language_follow_help", "Buyers see the form in the language they browse your store in.")
            }
          />
          {!shipped && (
            <Banner tone="info">
              <p>{t("setup.language_no_defaults", "COD King has no built-in texts for this language yet. Add your texts in Form designer → Texts, otherwise buyers see English.")}</p>
            </Banner>
          )}
          {value && shipped && (
            <Banner tone="info">
              <p>
                {t(
                  "setup.language_own_texts",
                  "COD King's own texts are translated for you. Texts you wrote yourself (offer titles, button labels, custom fields) show in this language only when you add a translation for it.",
                )}
              </p>
            </Banner>
          )}
        </BlockStack>
      </SectionCard>
    </div>
  );
};

export default LanguageCard;
