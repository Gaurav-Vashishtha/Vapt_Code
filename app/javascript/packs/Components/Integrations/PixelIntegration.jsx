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

const PixelIntegration = () => {
  const {
    setting: [setting, setSetting],
  } = useContext(StoreContext);

  const [pixelId, setPixelId] = useState(setting?.pixelId || "");
  const [pixelToken, setPixelToken] = useState(setting?.pixelToken || "");
  const [pixelTestEventId, setPixelTestEventId] = useState(
    setting?.pixelTestEventId || "",
  );
  const [conversionTracking, setConversionTracking] = useState(
    !!setting?.conversionTracking,
  );
  const [metaEventsEnabled, setMetaEventsEnabled] = useState(
    !!setting?.metaEventsEnabled,
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  // The save bar decides for itself when it is needed, the way it does on the
  // rest of the settings screens, rather than a button sitting in the card.
  const isDirty =
    pixelId !== (setting?.pixelId || "") ||
    pixelToken !== (setting?.pixelToken || "") ||
    pixelTestEventId !== (setting?.pixelTestEventId || "") ||
    conversionTracking !== !!setting?.conversionTracking ||
    metaEventsEnabled !== !!setting?.metaEventsEnabled;

  const handleDiscard = useCallback(() => {
    setPixelId(setting?.pixelId || "");
    setPixelToken(setting?.pixelToken || "");
    setPixelTestEventId(setting?.pixelTestEventId || "");
    setConversionTracking(!!setting?.conversionTracking);
    setMetaEventsEnabled(!!setting?.metaEventsEnabled);
    setError(null);
  }, [setting]);

  const handleSave = useCallback(async () => {
    setSaving(true);
    setError(null);
    try {
      const response = await Api.post("/settings", {
        ...setting,
        pixelId,
        pixelToken,
        pixelTestEventId,
        conversionTracking,
        metaEventsEnabled: metaEventsEnabled && conversionTracking && !!pixelId && !!pixelToken,
      });
      setSetting(response.data);
    } catch (err) {
      setError(I18n.t("admin.settings_error", { defaultValue: "Could not save integration." }));
    } finally {
      setSaving(false);
    }
  }, [
    setting,
    pixelId,
    pixelToken,
    pixelTestEventId,
    conversionTracking,
    metaEventsEnabled,
    setSetting,
  ]);

  return (
    <Page
      backAction={{
        content: I18n.t("integrations.title", { defaultValue: "Integrations" }),
        onAction: () => navigateTo("/integrations"),
      }}
      title={I18n.t("integrations.pixel.title", { defaultValue: "Meta Pixel" })}
      subtitle={
        I18n.t("integrations.pixel.subtitle", { defaultValue: "Send COD conversion events to Meta via the Conversions API." })
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
              title={I18n.t("integrations.pixel.help_title", { defaultValue: "Meta Pixel setup" })}
              description={
                I18n.t("integrations.pixel.help_description", { defaultValue: "Learn how to find your Pixel ID and Conversions API token." })
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
                I18n.t("integrations.pixel.credentials", { defaultValue: "Pixel credentials" })
              }
            >
              <BlockStack gap="400">
              <TextField
                label={I18n.t("integrations.pixel.pixel_id", { defaultValue: "Pixel ID" })}
                value={pixelId}
                onChange={setPixelId}
                autoComplete="off"
                placeholder="1234567890"
              />
              <TextField
                label={
                  I18n.t("integrations.pixel.pixel_token", { defaultValue: "Conversions API access token" })
                }
                value={pixelToken}
                onChange={setPixelToken}
                autoComplete="off"
                type="password"
              />
              <TextField
                label={
                  I18n.t("integrations.pixel.test_event_id", { defaultValue: "Test event ID" })
                }
                helpText={
                  I18n.t("integrations.pixel.test_event_help", { defaultValue: "Optional. Used to verify events in Meta Events Manager." })
                }
                value={pixelTestEventId}
                onChange={setPixelTestEventId}
                autoComplete="off"
              />
              <Checkbox
                label={
                  I18n.t("integrations.conversion_tracking", { defaultValue: "Enable conversion tracking" })
                }
                checked={conversionTracking}
                onChange={setConversionTracking}
              />
              <Checkbox
                label={
                  I18n.t("integrations.pixel.meta_events", { defaultValue: "Send full event funnel to Meta" })
                }
                helpText={
                  I18n.t("integrations.pixel.meta_events_help", { defaultValue: "Tracks page views, product views, add to cart, checkout and purchase from the storefront. Sends a browser event and a matching server event so Meta counts each action once. Requires the Pixel ID and Conversions API token above." })
                }
                checked={metaEventsEnabled}
                onChange={setMetaEventsEnabled}
                disabled={!conversionTracking || !pixelId || !pixelToken}
              />
              </BlockStack>
            </SectionCard>
          </BlockStack>
        </Layout.Section>
      </Layout>
    </Page>
  );
};

export default PixelIntegration;
