import React, { useCallback, useEffect, useState } from "react";
import { Badge, Banner, BlockStack, Button, Card, Divider, InlineStack, Modal, Text } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { codFormApi, parseError } from "../api";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { PIXEL_PLATFORMS } from "../constants";
import { newPixel } from "../defaults";
import { t } from "../i18n";
import Screen, { SaveErrorBanner } from "../components/Screen";
import EmptyState from "../components/EmptyState";
import ModuleDisabled from "../components/ModuleDisabled";
import PixelModal from "./PixelModal";
import KlaviyoOmnisendCard from "./KlaviyoOmnisendCard";
import { platformInfo } from "./platforms";

/**
 * /integrations/form-pixels and /integrations/tiktok — pixels the COD Form
 * fires (Meta, TikTok, GA4, Google Ads, Snapchat, Pinterest), plus Klaviyo
 * and Omnisend. On the TikTok path only TikTok pixels are listed.
 */
const FormPixelsPage = ({ path }) => {
  const bootstrap = useCodFormBootstrap();
  const tiktokOnly = path === "/integrations/tiktok";
  const [pixels, setPixels] = useState(null);
  const [integrations, setIntegrations] = useState([]);
  const [error, setError] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [modalError, setModalError] = useState(null);
  const [editing, setEditing] = useState(null);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(null);
  const [busy, setBusy] = useState(null);
  const [testResult, setTestResult] = useState(null);

  const load = useCallback(() => {
    setError(null);
    return codFormApi.pixels
      .index()
      .then((response) => setPixels(((response && response.items) || []).slice().sort((a, b) => (a.position || 0) - (b.position || 0))))
      .catch((err) => setError(parseError(err)));
  }, []);

  const loadIntegrations = useCallback(
    () =>
      codFormApi.integrations
        .index()
        .then((response) => setIntegrations((response && response.items) || []))
        .catch(() => setIntegrations([])),
    [],
  );

  useEffect(() => {
    if (!bootstrap || !bootstrap.moduleEnabled) return;
    load();
    if (!tiktokOnly) loadIntegrations();
  }, [bootstrap, load, loadIntegrations, tiktokOnly]);

  useEffect(() => {
    if (window.location.hash === "#klaviyo" || window.location.hash === "#omnisend") {
      const node = document.getElementById("codkf-crm");
      if (node && node.scrollIntoView) node.scrollIntoView({ block: "start" });
    }
  }, [integrations]);

  if (bootstrap && !bootstrap.moduleEnabled) return <ModuleDisabled />;

  const save = (pixel) => {
    setSaving(true);
    setModalError(null);
    const { id, ...body } = pixel;
    const request = id ? codFormApi.pixels.update(id, body) : codFormApi.pixels.create(body);
    request
      .then(() => {
        setEditing(null);
        return load();
      })
      .catch((err) => setModalError(parseError(err)))
      .then(() => setSaving(false));
  };

  const remove = () => {
    const pixel = deleting;
    setBusy(`del-${pixel.id}`);
    codFormApi.pixels
      .destroy(pixel.id)
      .then(() => load())
      .catch((err) => setActionError(parseError(err)))
      .then(() => {
        setBusy(null);
        setDeleting(null);
      });
  };

  const test = (pixel) => {
    setBusy(`test-${pixel.id}`);
    setTestResult(null);
    codFormApi.pixels
      .test(pixel.id)
      .then((response) => setTestResult({ id: pixel.id, ok: !!(response && response.ok) }))
      .catch(() => setTestResult({ id: pixel.id, ok: false }))
      .then(() => setBusy(null));
  };

  const list = (pixels || []).filter((pixel) => !tiktokOnly || pixel.platform === "tiktok");
  const platforms = tiktokOnly ? ["tiktok"] : PIXEL_PLATFORMS.filter((platform) => list.some((pixel) => pixel.platform === platform));
  const openNew = () => {
    setModalError(null);
    setEditing(newPixel(tiktokOnly ? "tiktok" : "meta"));
  };
  const integration = (provider) => integrations.find((item) => item.provider === provider) || null;

  return (
    <Screen
      title={tiktokOnly ? t("pixels.tiktok_title", "TikTok Pixel") : t("pixels.title", "COD Form pixels")}
      subtitle={
        tiktokOnly
          ? t("pixels.tiktok_subtitle", "Send COD Form events to TikTok from the browser and the Events API.")
          : t("pixels.subtitle", "Send form opens and orders to your ad platforms, from the browser and the server.")
      }
      backPath="/integrations"
      backLabel={t("pixels.back", "Integrations")}
      primaryAction={{ content: t("pixels.add_title", "Add pixel"), onAction: openNew }}
      loading={!bootstrap || (pixels === null && !error)}
      error={error}
      onRetry={load}
    >
      <SaveErrorBanner error={actionError} onDismiss={() => setActionError(null)} />
      {bootstrap && bootstrap.mode !== "cod_form" && (
        <Banner tone="info" action={{ content: t("pixels.open_setup", "Open COD Form setup"), onAction: () => navigateTo("/features/cod-form") }}>
          <p>{t("pixels.mode_off", "These pixels fire for COD Form orders. COD Form is currently off.")}</p>
        </Banner>
      )}
      {!tiktokOnly && (
        <Banner tone="info">
          <p>{t("pixels.meta_note", "The Meta pixel you set under Integrations → Meta Pixel keeps working for form orders. Add pixels here only if you need more of them, or other platforms.")}</p>
        </Banner>
      )}

      {list.length === 0 ? (
        <EmptyState heading={t("pixels.empty_title", "No pixel added yet")} action={{ content: t("pixels.add_title", "Add pixel"), onAction: openNew }}>
          <p>{t("pixels.empty_body", "Add a pixel to report form opens and orders to your ad platform. Tracking follows the buyer's cookie consent.")}</p>
        </EmptyState>
      ) : (
        platforms.map((platform) => (
          <Card key={platform}>
            <BlockStack gap="300">
              <Text as="h2" variant="headingMd">
                {platformInfo(platform).name}
              </Text>
              {list
                .filter((pixel) => pixel.platform === platform)
                .map((pixel, index) => (
                  <React.Fragment key={pixel.id}>
                    {index > 0 && <Divider />}
                    <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
                      <BlockStack gap="050">
                        <InlineStack gap="200" blockAlign="center" wrap>
                          <Text as="span" variant="bodyMd" fontWeight="semibold" breakWord>
                            {pixel.pixel_id}
                          </Text>
                          {pixel.enabled === false ? (
                            <Badge>{t("common.disabled", "Off")}</Badge>
                          ) : (
                            <Badge tone="success">{t("common.enabled", "On")}</Badge>
                          )}
                          {pixel.config && pixel.config.purchase_event === "lead" && <Badge tone="info">{t("pixels.purchase_event_lead", "Lead")}</Badge>}
                          {pixel.targeting && pixel.targeting.scope === "selected" && <Badge>{t("pixels.targeted_badge", "Selected products")}</Badge>}
                        </InlineStack>
                        <Text as="span" variant="bodySm" tone="subdued">
                          {[
                            pixel.config && pixel.config.browser !== false ? t("pixels.browser_short", "Browser") : null,
                            pixel.config && pixel.config.server ? t("pixels.server_short", "Server") : null,
                            pixel.access_token_masked ? pixel.access_token_masked : null,
                          ]
                            .filter(Boolean)
                            .join(" · ")}
                        </Text>
                        {testResult && testResult.id === pixel.id && (
                          <Text as="span" variant="bodySm" tone={testResult.ok ? "success" : "critical"}>
                            {testResult.ok
                              ? t("pixels.test_ok", "Test event accepted by the platform.")
                              : t("pixels.test_failed", "The test event was rejected. Check the ID and the token.")}
                          </Text>
                        )}
                      </BlockStack>
                      <InlineStack gap="200" wrap>
                        {pixel.config && pixel.config.server && (
                          <Button onClick={() => test(pixel)} loading={busy === `test-${pixel.id}`}>
                            {t("pixels.test", "Send test event")}
                          </Button>
                        )}
                        <Button onClick={() => { setModalError(null); setEditing(pixel); }}>{t("common.edit", "Edit")}</Button>
                        <Button tone="critical" onClick={() => setDeleting(pixel)}>
                          {t("common.delete", "Delete")}
                        </Button>
                      </InlineStack>
                    </InlineStack>
                  </React.Fragment>
                ))}
            </BlockStack>
          </Card>
        ))
      )}

      {!tiktokOnly && (
        <div id="codkf-crm">
          <BlockStack gap="400">
            <Text as="h2" variant="headingMd">
              {t("integrations.crm_title", "Email and SMS marketing")}
            </Text>
            <KlaviyoOmnisendCard provider="klaviyo" item={integration("klaviyo")} onChanged={loadIntegrations} />
            <KlaviyoOmnisendCard provider="omnisend" item={integration("omnisend")} onChanged={loadIntegrations} />
          </BlockStack>
        </div>
      )}

      <PixelModal
        open={!!editing}
        pixel={editing}
        pixels={pixels || []}
        lockedPlatform={tiktokOnly}
        saving={saving}
        error={modalError}
        onClose={() => setEditing(null)}
        onSave={save}
      />
      <Modal
        open={!!deleting}
        onClose={() => setDeleting(null)}
        title={t("pixels.delete_title", "Delete this pixel?")}
        primaryAction={{ content: t("common.delete", "Delete"), destructive: true, onAction: remove, loading: !!deleting && busy === `del-${deleting.id}` }}
        secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: () => setDeleting(null) }]}
      >
        <Modal.Section>
          <Text as="p">{t("pixels.delete_body", "Form events are no longer sent to %{id}.", { id: deleting ? deleting.pixel_id : "" })}</Text>
        </Modal.Section>
      </Modal>
    </Screen>
  );
};

export default FormPixelsPage;
