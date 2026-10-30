import React, { useState } from "react";
import { BlockStack, Box, Checkbox, Select, Text } from "@shopify/polaris";
import { codFormApi } from "../api";
import useCodFormBootstrap, { refreshBootstrap } from "../useCodFormBootstrap";
import useFormLanguage, { setFormLanguage } from "../useFormLanguage";
import { SHIPPED_LOCALES, localeName } from "../constants";
import { t } from "../i18n";

/**
 * Quick onboarding, "choose your features" step: the COD Form as one more feature next to
 * OTP verification and partial payment (DSH-8). Ticking it turns the form on for the store
 * (the same switch as COD Form > Setup); unticking turns it off. Renders nothing for shops
 * without the module.
 */
const OnboardingSetupStep = () => {
  const bootstrap = useCodFormBootstrap();
  const [pending, setPending] = useState(null); // the value being saved, or null
  const [failed, setFailed] = useState(false);
  const language = useFormLanguage();
  if (!bootstrap || !bootstrap.moduleEnabled) return null;

  const isOn = pending !== null ? pending : bootstrap.mode === "cod_form";
  const change = (checked) => {
    if (pending !== null) return;
    setPending(checked);
    setFailed(false);
    codFormApi.setup
      .mode(checked ? "cod_form" : "legacy")
      .then(() => refreshBootstrap())
      .catch(() => setFailed(true))
      .then(() => setPending(null));
  };

  return (
    <Box padding="400" background="bg-surface-secondary" borderRadius="200">
      <BlockStack gap="200">
        <Checkbox
          label={t("onboarding.title", "COD Form")}
          checked={isOn}
          disabled={pending !== null}
          onChange={change}
        />
        <Box paddingInlineStart="600">
          <BlockStack gap="200">
            {isOn && (
              <Box maxWidth="320px" paddingBlockEnd="100">
                <Select
                  label={t("setup.language_title", "Form language")}
                  options={[
                    { value: "", label: t("setup.language_follow", "Storefront language (default)") },
                    ...SHIPPED_LOCALES.map((code) => ({ value: code, label: localeName(code) })),
                  ]}
                  value={language.value}
                  disabled={!language.loaded || language.saving}
                  onChange={(next) => setFormLanguage(next)}
                  helpText={
                    language.failed
                      ? undefined
                      : language.value
                        ? t("setup.language_fixed_help", "Every buyer sees the form in this language, whatever language your storefront is in.")
                        : t("setup.language_follow_help", "Buyers see the form in the language they browse your store in.")
                  }
                  error={language.failed ? t("onboarding.error", "This could not be saved. Try again.") : undefined}
                />
              </Box>
            )}
            <Text variant="bodySm" as="p" tone="subdued">
              {t("onboarding.body", "A Buy with COD button and a one-page order form on your store. Buyers order without going through checkout.")}
            </Text>
            <Text variant="bodySm" as="p" tone="subdued">
              {t("onboarding.buttons_note", "It works on its own: it adds a new Buy with COD button to your store. Phone verification, partial payment and your other COD King features keep working on your store's own Buy now and Checkout buttons, so you can use them together or separately.")}
            </Text>
            {isOn && (
              <Text variant="bodySm" as="p" tone="subdued">
                {t("onboarding.next", "Next, you will switch on the COD Form app embed in your theme. You can change the form's fields, texts and colours later under Settings > COD Form.")}
              </Text>
            )}
            {failed && (
              <Text variant="bodySm" as="p" tone="critical">
                {t("onboarding.error", "This could not be saved. Try again.")}
              </Text>
            )}
          </BlockStack>
        </Box>
      </BlockStack>
    </Box>
  );
};

export default OnboardingSetupStep;
