import React, { useEffect, useRef, useState } from "react";
import {
  Banner,
  BlockStack,
  Button,
  Checkbox,
  ChoiceList,
  InlineGrid,
  InlineStack,
  Spinner,
  Text,
} from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { codFormApi } from "../api";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { DEFAULT_FORM_CONFIG, FORM_THEMES } from "../defaults";
import { t } from "../i18n";
import FormMock from "./FormMock";
import OnboardingEmbedStep from "./OnboardingEmbedStep";

const isHex = (value) => /^#[0-9a-fA-F]{6}$/.test(value || "");

/**
 * Custom setup page, "COD Form" section: the few settings a new store needs first — the app
 * embed, the form's look (theme and button colour) and phone verification — with a preview.
 * Everything else stays under Settings > COD Form. `onContinue` runs after a successful save.
 */
const CustomSetupCodForm = ({ onContinue }) => {
  const bootstrap = useCodFormBootstrap();
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState(null); // the default form, or null when there is none
  const [design, setDesign] = useState(null);
  const [otpOn, setOtpOn] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(false);
  const saved = useRef({ design: null, otpOn: null });
  const alive = useRef(true);

  useEffect(() => {
    alive.current = true;
    const loadForm = codFormApi.forms
      .index()
      .then((data) => {
        const list = Array.isArray(data) ? data : (data && (data.items || data.forms)) || [];
        const first = list.find((item) => item.is_default) || list[0];
        return first ? codFormApi.forms.show(first.id) : null;
      })
      .then((data) => (data && data.form ? data.form : data))
      .catch(() => null);
    const loadSetup = codFormApi.setup.show().catch(() => null);
    Promise.all([loadForm, loadSetup]).then(([loadedForm, setup]) => {
      if (!alive.current) return;
      const otp = setup && setup.general && setup.general.otp;
      const on = !!(otp && otp.enabled === true);
      const loadedDesign = loadedForm && loadedForm.draft_config ? loadedForm.draft_config.design || {} : null;
      setForm(loadedForm && loadedForm.draft_config ? loadedForm : null);
      setDesign(loadedDesign);
      setOtpOn(on);
      saved.current = { design: loadedDesign, otpOn: on };
      setLoading(false);
    });
    return () => {
      alive.current = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (loading) {
    return (
      <InlineStack align="center">
        <Spinner size="small" />
      </InlineStack>
    );
  }

  const theme = design && design.theme === "express" ? "express" : "classic";
  const pickTheme = (value) => {
    if (value === theme) return;
    setDesign((current) => ({ ...(current || {}), ...FORM_THEMES[value], theme: value }));
  };
  const setPrimary = (value) => setDesign((current) => ({ ...(current || {}), primary: value }));

  const save = async () => {
    setSaving(true);
    setError(false);
    try {
      if (form && design !== saved.current.design) {
        const draft = { ...form.draft_config, design };
        const updated = await codFormApi.forms.update(form.id, { draft_config: draft });
        await codFormApi.forms.publish(form.id);
        const next = updated && updated.form ? updated.form : updated;
        if (alive.current && next && next.draft_config) setForm(next);
        saved.current.design = design;
      }
      if (otpOn !== saved.current.otpOn) {
        await codFormApi.setup.update({ otp: { enabled: otpOn } });
        saved.current.otpOn = otpOn;
      }
      if (window.shopify && window.shopify.toast) {
        window.shopify.toast.show(t("custom_setup.saved", "COD Form settings saved"));
      }
      if (onContinue) onContinue();
    } catch (err) {
      if (alive.current) setError(true);
    } finally {
      if (alive.current) setSaving(false);
    }
  };

  const previewConfig = form
    ? { ...form.draft_config, design: design || form.draft_config.design }
    : DEFAULT_FORM_CONFIG;

  return (
    <InlineGrid columns={{ xs: "1fr", md: "minmax(0,1fr) minmax(300px,380px)" }} gap="500">
      <BlockStack gap="500">
        <OnboardingEmbedStep />

        {form && (
          <BlockStack gap="300">
            <Text as="h3" variant="headingSm">
              {t("custom_setup.look_title", "Look of the form")}
            </Text>
            <ChoiceList
              title={t("designer.theme_title", "Theme")}
              choices={[
                {
                  value: "classic",
                  label: t("designer.theme_classic", "Classic"),
                  helpText: t("designer.theme_classic_help", "Large labels beside the fields and a big order button."),
                },
                {
                  value: "express",
                  label: t("designer.theme_express", "Express"),
                  helpText: t(
                    "designer.theme_express_help",
                    "The look of the COD King checkout: white cards, small labels above the fields and a compact button.",
                  ),
                },
              ]}
              selected={[theme]}
              onChange={(value) => pickTheme(value[0])}
            />
            <InlineStack gap="300" blockAlign="center">
              <input
                type="color"
                aria-label={t("custom_setup.button_colour", "Order button colour")}
                value={isHex(design && design.primary) ? design.primary : "#000000"}
                onChange={(event) => setPrimary(event.target.value)}
                style={{ width: 44, height: 32, padding: 0, border: "1px solid #c9cccf", borderRadius: 6, background: "none", cursor: "pointer" }}
              />
              <Text as="span" variant="bodyMd">
                {t("custom_setup.button_colour", "Order button colour")}
              </Text>
            </InlineStack>
          </BlockStack>
        )}

        <BlockStack gap="200">
          <Text as="h3" variant="headingSm">
            {t("custom_setup.verify_title", "Phone verification")}
          </Text>
          <Checkbox
            label={t("fraud.otp_enable", "Ask buyers to verify their phone number with a code")}
            helpText={t("fraud.otp_enable_help", "Applies to the COD Form only. Your other COD King checkout settings are not changed.")}
            checked={otpOn}
            onChange={setOtpOn}
          />
        </BlockStack>

        {error && (
          <Banner tone="critical" onDismiss={() => setError(false)}>
            <p>{t("custom_setup.error", "These settings could not be saved. Try again.")}</p>
          </Banner>
        )}

        <InlineStack gap="300" blockAlign="center" wrap>
          <Button variant="primary" onClick={save} loading={saving}>
            {t("custom_setup.save", "Save and continue")}
          </Button>
          <Button variant="plain" onClick={() => navigateTo("/features/cod-form/designer")}>
            {t("custom_setup.open_designer", "Fields, texts and more in the form designer")}
          </Button>
          <Button variant="plain" onClick={() => navigateTo("/features/cod-form/buttons")}>
            {t("custom_setup.open_buttons", "Buy with COD button")}
          </Button>
          <Button variant="plain" onClick={() => navigateTo("/features/cod-form/shipping")}>
            {t("custom_setup.open_shipping", "Shipping rates")}
          </Button>
        </InlineStack>
      </BlockStack>

      <div style={{ maxHeight: 620, overflow: "auto", borderRadius: 12, background: "#6b7280", padding: "16px 10px 0" }}>
        <FormMock
          config={previewConfig}
          defaultsTexts={null}
          locale="en"
          device="mobile"
          view="form"
          moneyFormat={bootstrap ? bootstrap.moneyFormat : undefined}
          currency={bootstrap ? bootstrap.currency : undefined}
          shopCountry={bootstrap ? bootstrap.shopCountry : undefined}
        />
      </div>
    </InlineGrid>
  );
};

export default CustomSetupCodForm;
