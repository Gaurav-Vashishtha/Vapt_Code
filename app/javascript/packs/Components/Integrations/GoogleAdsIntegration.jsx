import React, { useContext, useState, useCallback } from "react";
import {
  Page,
  Layout,
  BlockStack,
  TextField,
  Checkbox,
  Banner,
} from "@shopify/polaris";
import { SaveBar } from "@shopify/app-bridge-react";
import { StoreContext } from "../../Context/Store";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import { navigateTo } from "../../../utils/navigate";
import FeatureCallout from "../FeatureCallout";
import { SectionCard } from "../SettingsPrimitives";

const GoogleAdsIntegration = () => {
  const {
    setting: [setting, setSetting],
  } = useContext(StoreContext);

  const [googleConversionId, setGoogleConversionId] = useState(
    setting?.googleConversionId || "",
  );
  const [googleConversionLabel, setGoogleConversionLabel] = useState(
    setting?.googleConversionLabel || "",
  );
  const [googleConversionToken, setGoogleConversionToken] = useState(
    setting?.googleConversionToken || "",
  );
  const [conversionTracking, setConversionTracking] = useState(
    !!setting?.conversionTracking,
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  // The save bar decides for itself when it is needed, the way it does on the
  // rest of the settings screens, rather than a button sitting in the card.
  const isDirty =
    googleConversionId !== (setting?.googleConversionId || "") ||
    googleConversionLabel !== (setting?.googleConversionLabel || "") ||
    googleConversionToken !== (setting?.googleConversionToken || "") ||
    conversionTracking !== !!setting?.conversionTracking;

  const handleDiscard = useCallback(() => {
    setGoogleConversionId(setting?.googleConversionId || "");
    setGoogleConversionLabel(setting?.googleConversionLabel || "");
    setGoogleConversionToken(setting?.googleConversionToken || "");
    setConversionTracking(!!setting?.conversionTracking);
    setError(null);
  }, [setting]);

  const handleSave = useCallback(async () => {
    setSaving(true);
    setError(null);
    try {
      const response = await Api.post("/settings", {
        ...setting,
        googleConversionId,
        googleConversionLabel,
        googleConversionToken,
        conversionTracking,
      });
      setSetting(response.data);
    } catch (err) {
      setError(I18n.t("admin.settings_error", { defaultValue: "Could not save integration." }));
    } finally {
      setSaving(false);
    }
  }, [
    setting,
    googleConversionId,
    googleConversionLabel,
    googleConversionToken,
    conversionTracking,
    setSetting,
  ]);

  return (
    <Page
      backAction={{
        content: I18n.t("integrations.title", { defaultValue: "Integrations" }),
        onAction: () => navigateTo("/integrations"),
      }}
      title={I18n.t("integrations.google_ads.title", { defaultValue: "Google Ads" })}
      subtitle={
        I18n.t("integrations.google_ads.subtitle", { defaultValue: "Track COD conversions in Google Ads." })
      }
      fullWidth
    >
      <SaveBar data-save-bar open={isDirty}>
        <button
          variant="primary"
          onClick={handleSave}
          loading={saving ? "" : undefined}
          disabled={saving}
        >
          {I18n.t("admin.save", { defaultValue: "Save" })}
        </button>
        <button onClick={handleDiscard}>
          {I18n.t("admin.discard", { defaultValue: "Discard" })}
        </button>
      </SaveBar>

      <Layout>
        <Layout.Section>
          <BlockStack gap="400">
            <FeatureCallout
              illustration="docs"
              title={I18n.t("integrations.google_ads.help_title", { defaultValue: "Google Ads setup" })}
              description={
                I18n.t("integrations.google_ads.help_description", { defaultValue: "Learn where to find your conversion ID and label." })
              }
              docsUrl="https://codking.tech/documentation/"
              showChat
            />

            {error && (
              <Banner tone="critical" onDismiss={() => setError(null)}>
                {error}
              </Banner>
            )}

            <SectionCard
              title={
                I18n.t("integrations.google_ads.credentials", { defaultValue: "Conversion details" })
              }
            >
              <BlockStack gap="400">
              <TextField
                label={
                  I18n.t("integrations.google_ads.conversion_id", { defaultValue: "Conversion ID" })
                }
                value={googleConversionId}
                onChange={setGoogleConversionId}
                autoComplete="off"
                placeholder={I18n.t("google_ads_integration.aw_123456789")}
              />
              <TextField
                label={
                  I18n.t("integrations.google_ads.conversion_label", { defaultValue: "Conversion label" })
                }
                value={googleConversionLabel}
                onChange={setGoogleConversionLabel}
                autoComplete="off"
              />
              <TextField
                label={
                  I18n.t("integrations.google_ads.conversion_token", { defaultValue: "Conversion API token" })
                }
                helpText={
                  I18n.t("integrations.google_ads.conversion_token_help", { defaultValue: "Optional. Used for server-side conversion uploads." })
                }
                value={googleConversionToken}
                onChange={setGoogleConversionToken}
                autoComplete="off"
                type="password"
              />
              <Checkbox
                label={
                  I18n.t("integrations.conversion_tracking", { defaultValue: "Enable conversion tracking" })
                }
                checked={conversionTracking}
                onChange={setConversionTracking}
              />
              </BlockStack>
            </SectionCard>
          </BlockStack>
        </Layout.Section>
      </Layout>
    </Page>
  );
};

export default GoogleAdsIntegration;
