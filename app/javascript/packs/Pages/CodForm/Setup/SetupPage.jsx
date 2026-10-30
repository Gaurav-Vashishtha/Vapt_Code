import React, { useCallback, useEffect, useState } from "react";
import { Layout, BlockStack } from "@shopify/polaris";
import { codFormApi } from "../api";
import useResource from "../useResource";
import useCodFormBootstrap, { refreshBootstrap } from "../useCodFormBootstrap";
import { DEFAULT_GENERAL } from "../defaults";
import { mergeDefaults, setIn } from "../utils";
import { t } from "../i18n";
import Screen, { SaveErrorBanner } from "../components/Screen";
import ScreenSaveBar from "../components/ScreenSaveBar";
import ModeCard from "./ModeCard";
import EmbedStatusCard from "./EmbedStatusCard";
import ChecklistCard from "./ChecklistCard";
import HealthCard from "./HealthCard";
import CountriesCard from "./CountriesCard";
import VisibilityCard from "./VisibilityCard";
import UsageCard from "./UsageCard";
import AutocompleteCard from "./AutocompleteCard";
import LanguageCard from "./LanguageCard";
import OtpModeCard from "../Fraud/OtpModeCard";

export const prepare = (raw) => ({
  ...(raw || {}),
  general: mergeDefaults(DEFAULT_GENERAL, (raw && raw.general) || {}),
});

/**
 * /features/cod-form — Setup (spec §12, DSH-5/6/11): app embed, mode, countries, visibility,
 * form language, OTP verification and address autocomplete. Shipping rates, order total limits and the other
 * optional behaviour live under Advanced settings in the side panel (AdvancedSettingsPage).
 */
const SetupPage = () => {
  const bootstrap = useCodFormBootstrap();
  const resource = useResource({
    load: () => codFormApi.setup.show(),
    // The form language adds a language to every "Language" picker (bootstrap.locales).
    save: (data) =>
      codFormApi.setup.update(data.general).then((response) => {
        refreshBootstrap();
        return response;
      }),
    prepare,
  });
  const { data, setData, isDirty, loading, saving, error, saveError, save, discard, reload, clearSaveError } = resource;

  const [switching, setSwitching] = useState(false);
  const [modeError, setModeError] = useState(false);
  const [republishing, setRepublishing] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [embedOverride, setEmbedOverride] = useState(null);

  const change = useCallback(
    (path, value) => setData((current) => setIn(current, ["general", ...path], value)),
    [setData],
  );

  const switchMode = useCallback(
    (mode) => {
      setSwitching(true);
      setModeError(false);
      return codFormApi.setup
        .mode(mode)
        .then(() => refreshBootstrap())
        .then(() => {
          setEmbedOverride(null);
          return reload();
        })
        .catch(() => setModeError(true))
        .then(() => setSwitching(false));
    },
    [reload],
  );

  const refreshEmbed = useCallback(() => {
    setRefreshing(true);
    codFormApi.setup
      .refreshEmbed()
      .then((response) => {
        if (response && response.embed) setEmbedOverride(response.embed);
      })
      .catch(() => {})
      .then(() => setRefreshing(false));
  }, []);

  // Deep link from the Integrations directory: /features/cod-form#address-autocomplete
  const loaded = !!data;
  useEffect(() => {
    if (!loaded || !window.location.hash) return;
    const node = document.getElementById(window.location.hash.slice(1));
    if (node && node.scrollIntoView) node.scrollIntoView({ block: "start" });
  }, [loaded]);

  const embed = embedOverride || (data && data.embed) || {};
  const health = (data && data.health) || [];
  const usage = (data && data.usage) || (bootstrap && bootstrap.usage);
  // Express checkout running next to the form is normal: it is not called out anywhere.
  const showLegacyWarning = false;
  const healthItems = health.filter((item) => item.code !== "legacy_embed_on");

  // The checklist leads the page until every step is done, then it goes away. The test-order
  // step is no longer offered, so it never keeps the checklist open.
  const checklistOpen = ((data && data.checklist) || []).some((item) => item.key !== "test_order" && !item.done);

  // Writes everything saved to the storefront again, whether or not anything changed.
  const republish = () => {
    const say = (message, isError) => window.shopify && window.shopify.toast && window.shopify.toast.show(message, { isError });
    setRepublishing(true);
    codFormApi.sync
      .publish()
      .then(
        (sync) =>
          sync && sync.status !== "failed" && !(sync.form_errors || []).length
            ? say(t("common.resync_done", "Settings synced to your storefront"))
            : say(t("setup.resync_failed", "Could not sync to your storefront. Try again in a moment."), true),
        () => say(t("setup.resync_failed", "Could not sync to your storefront. Try again in a moment."), true),
      )
      .then(() => setRepublishing(false));
  };

  return (
    <Screen
      title={t("setup.title", "COD Form setup")}
      secondaryActions={[
        { content: t("setup.resync", "Resync settings to storefront"), onAction: republish, loading: republishing, disabled: isDirty },
      ]}
      subtitle={t("setup.subtitle", "Turn the form on, choose where it shows and check that everything is ready.")}
      loading={loading || !data}
      error={error}
      onRetry={reload}
      skeletonCards={4}
    >
      {data && (
        <>
          <ScreenSaveBar open={isDirty} saving={saving} onSave={save} onDiscard={discard} />
          <SaveErrorBanner error={saveError} onDismiss={clearSaveError} />
          <Layout>
            <Layout.Section>
              <BlockStack gap="400">
                {checklistOpen && (
                  <ChecklistCard checklist={data.checklist} themeEditorUrl={embed.theme_editor_url} />
                )}
                <EmbedStatusCard
                  embed={embed}
                  showLegacyWarning={showLegacyWarning}
                  refreshing={refreshing}
                  onRefresh={refreshEmbed}
                />
                <ModeCard
                  mode={data.mode || (bootstrap && bootstrap.mode)}
                  legacyModeLabel={bootstrap && bootstrap.legacyModeLabel}
                  switching={switching}
                  error={modeError}
                  disabled={isDirty}
                  embedOff={embed.enabled === false}
                  onSwitch={switchMode}
                />
                <LanguageCard general={data.general} onChange={change} locales={bootstrap && bootstrap.locales} />
                <OtpModeCard
                  otp={data.general.otp || {}}
                  onChange={change}
                  title={t("setup.otp_title", "OTP verification")}
                />
                <VisibilityCard general={data.general} onChange={change} />
                <CountriesCard general={data.general} onChange={change} />
                <AutocompleteCard general={data.general} onChange={change} />
              </BlockStack>
            </Layout.Section>
            <Layout.Section variant="oneThird">
              <BlockStack gap="400">
                <HealthCard health={healthItems} />
                <UsageCard usage={usage} tier={bootstrap && bootstrap.tier} />
              </BlockStack>
            </Layout.Section>
          </Layout>
        </>
      )}
    </Screen>
  );
};

export default SetupPage;
