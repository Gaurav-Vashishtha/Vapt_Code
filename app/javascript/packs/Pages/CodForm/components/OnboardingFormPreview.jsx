import React, { useEffect, useState } from "react";
import { BlockStack, Card, Text } from "@shopify/polaris";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { DEFAULT_FORM_CONFIG } from "../defaults";
import { t } from "../i18n";
import FormMock from "./FormMock";
import useFormLanguage from "../useFormLanguage";
import loadFormDefaults from "../Designer/formDefaults";

/** True while the store has the COD Form module and the form is switched on. */
export const useCodFormOn = () => {
  const bootstrap = useCodFormBootstrap();
  return !!(bootstrap && bootstrap.moduleEnabled && bootstrap.mode === "cod_form");
};

/**
 * Quick onboarding, right-hand column: what the COD Form looks like to a buyer (the default
 * form with sample products). Renders nothing while the form is off.
 */
const OnboardingFormPreview = ({ height = 620 }) => {
  const bootstrap = useCodFormBootstrap();
  const language = useFormLanguage();
  const [defaultsTexts, setDefaultsTexts] = useState(null);
  useEffect(() => {
    let live = true;
    loadFormDefaults().then((defaults) => live && setDefaultsTexts(defaults.texts));
    return () => {
      live = false;
    };
  }, []);
  if (!bootstrap || !bootstrap.moduleEnabled || bootstrap.mode !== "cod_form") return null;
  // "" (storefront language) previews in the store's main language.
  const locale = language.value || (bootstrap.locales && bootstrap.locales[0]) || "en";
  return (
    <Card>
      <BlockStack gap="300">
        <BlockStack gap="050">
          <Text variant="headingSm" as="h3">
            {t("onboarding.preview_title", "COD Form")}
          </Text>
          <Text variant="bodySm" as="p" tone="subdued">
            {t("onboarding.preview_help", "Opens when a buyer taps the new Buy with COD button. You can change the fields, texts and colours later.")}
          </Text>
        </BlockStack>
        <div style={{ maxHeight: height, overflow: "auto", borderRadius: 12, background: "#6b7280", padding: "16px 10px 0" }}>
          <FormMock
            config={DEFAULT_FORM_CONFIG}
            key={locale}
            defaultsTexts={defaultsTexts}
            locale={locale}
            device="mobile"
            view="form"
            moneyFormat={bootstrap.moneyFormat}
            currency={bootstrap.currency}
            shopCountry={bootstrap.shopCountry}
          />
        </div>
      </BlockStack>
    </Card>
  );
};

export default OnboardingFormPreview;
