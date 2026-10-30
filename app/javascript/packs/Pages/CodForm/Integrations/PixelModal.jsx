import React, { useEffect, useState } from "react";
import { Modal, Banner, BlockStack, Checkbox, ChoiceList, Divider, InlineGrid, Select, Text, TextField } from "@shopify/polaris";
import ResourceTargetPicker from "../components/ResourceTargetPicker";
import { SaveErrorBanner } from "../components/Screen";
import { useGate, UpgradeCard } from "../components/Gate";
import { FEATURES, LIMITS, PIXEL_PLATFORMS } from "../constants";
import { withPixelDefaults } from "../defaults";
import { t } from "../i18n";
import { gateForNewPixel, pixelIdError, platformInfo } from "./platforms";

/**
 * Add / edit a tracking pixel (TRK-2, TRK-3, TRK-7, TRK-8). The access token
 * is write-only: the API returns it masked, and it is sent only when typed.
 */
const PixelModal = ({ open, pixel, pixels, lockedPlatform, saving, error, onClose, onSave }) => {
  const [draft, setDraft] = useState(null);
  const [token, setToken] = useState("");
  const p3Gate = useGate(FEATURES.PIXELS_P3);
  const extraGate = useGate(FEATURES.EXTRA_PIXELS);

  useEffect(() => {
    if (open) {
      setDraft(withPixelDefaults(pixel));
      setToken("");
    }
  }, [open, pixel]);

  if (!draft) return null;
  const isNew = !draft.id;
  const info = platformInfo(draft.platform);
  const config = draft.config || {};
  const targeting = draft.targeting || {};
  const others = (pixels || []).filter((item) => item.id !== draft.id);
  const samePlatform = others.filter((item) => item.platform === draft.platform);
  const atLimit = isNew && samePlatform.length >= LIMITS.PIXELS_PER_PLATFORM;
  const neededGate = isNew ? gateForNewPixel(draft.platform, others) : null;
  const gateBlocked =
    (neededGate === FEATURES.PIXELS_P3 && !p3Gate.allowed) || (neededGate === FEATURES.EXTRA_PIXELS && !extraGate.allowed);
  const duplicate = samePlatform.some((item) => String(item.pixel_id).trim() === String(draft.pixel_id).trim() && draft.pixel_id);
  const idError = draft.pixel_id ? pixelIdError(draft.platform, draft.pixel_id) : undefined;
  const serverNeedsToken = info.hasToken && config.server && isNew && !token;
  const productTargeting = targeting.scope === "selected";
  const invalid =
    !!pixelIdError(draft.platform, draft.pixel_id) ||
    duplicate ||
    atLimit ||
    gateBlocked ||
    (info.hasConversionLabel && !config.conversion_label) ||
    (info.hasAdAccount && config.server && !config.ad_account_id) ||
    (productTargeting && !p3Gate.allowed) ||
    (productTargeting && (targeting.product_ids || []).length === 0 && (targeting.collection_ids || []).length === 0);

  const set = (key, value) => setDraft((current) => ({ ...current, [key]: value }));
  const setConfig = (key, value) => setDraft((current) => ({ ...current, config: { ...(current.config || {}), [key]: value } }));
  const setEvent = (key, value) =>
    setDraft((current) => ({
      ...current,
      config: { ...(current.config || {}), events: { ...((current.config || {}).events || {}), [key]: value } },
    }));

  const submit = () => {
    const { access_token_masked: _masked, access_token: _unused, ...body } = draft;
    const payload = { ...body, pixel_id: String(draft.pixel_id).trim() };
    if (token) payload.access_token = token.trim();
    onSave(payload);
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isNew ? t("pixels.add_title", "Add pixel") : t("pixels.edit_title", "Edit %{name}", { name: info.name })}
      primaryAction={{ content: t("common.save", "Save"), onAction: submit, loading: saving, disabled: invalid }}
      secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: onClose }]}
      large
    >
      <Modal.Section>
        <BlockStack gap="400">
          <SaveErrorBanner error={error} />
          {isNew && !lockedPlatform && (
            <Select
              label={t("pixels.platform", "Platform")}
              options={PIXEL_PLATFORMS.map((platform) => ({ value: platform, label: platformInfo(platform).name }))}
              value={draft.platform}
              onChange={(value) => setDraft((current) => withPixelDefaults({ ...current, platform: value, pixel_id: "" }))}
            />
          )}
          {gateBlocked && (
            <UpgradeCard
              compact
              minTier={neededGate === FEATURES.PIXELS_P3 ? p3Gate.minTier : extraGate.minTier}
              title={
                neededGate === FEATURES.PIXELS_P3
                  ? t("pixels.p3_locked", "Snapchat and Pinterest pixels")
                  : t("pixels.extra_locked", "More than one pixel per platform")
              }
            />
          )}
          {atLimit && (
            <Banner tone="warning">
              <p>{t("pixels.limit_reached", "You can add up to 5 pixels per platform.")}</p>
            </Banner>
          )}
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            <TextField
              label={info.idLabel}
              value={draft.pixel_id || ""}
              onChange={(value) => set("pixel_id", value)}
              placeholder={info.idPlaceholder}
              error={duplicate ? t("pixels.error_duplicate", "This ID is already added.") : idError}
              autoComplete="off"
            />
            {info.hasConversionLabel && (
              <TextField
                label={t("pixels.conversion_label", "Conversion label")}
                value={config.conversion_label || ""}
                onChange={(value) => setConfig("conversion_label", value.trim())}
                placeholder="AbC-D_efG"
                autoComplete="off"
              />
            )}
            {info.hasAdAccount && (
              <TextField
                label={t("pixels.ad_account_id", "Ad account ID")}
                value={config.ad_account_id || ""}
                onChange={(value) => setConfig("ad_account_id", value.trim())}
                helpText={t("pixels.ad_account_help", "Needed to send events from the server.")}
                autoComplete="off"
              />
            )}
          </InlineGrid>
          {info.hasToken && (
            <TextField
              label={info.tokenLabel}
              value={token}
              onChange={setToken}
              type="password"
              placeholder={draft.access_token_masked || ""}
              helpText={
                draft.access_token_masked
                  ? t("pixels.token_saved_help", "A token is saved. Type a new one only to replace it.")
                  : t("pixels.token_help", "Needed for server events. It is stored securely and never shown again.")
              }
              autoComplete="off"
            />
          )}
          <Divider />
          <Text as="h3" variant="headingSm">
            {t("pixels.sending_title", "What to send")}
          </Text>
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="200">
            <Checkbox label={t("pixels.browser", "Send from the browser")} checked={config.browser !== false} onChange={(value) => setConfig("browser", value)} />
            {info.hasToken || info.hasConversionLabel ? (
              <Checkbox
                label={t("pixels.server", "Send from the server too")}
                helpText={t("pixels.server_help", "Browser and server events share an ID, so each one is counted once.")}
                checked={!!config.server}
                onChange={(value) => setConfig("server", value)}
              />
            ) : null}
          </InlineGrid>
          {serverNeedsToken && (
            <Banner tone="warning">
              <p>{t("pixels.token_missing", "Server events need the access token. Without it only browser events are sent.")}</p>
            </Banner>
          )}
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="200">
            <Checkbox
              label={t("pixels.event_form_open", "Form opened (initiate checkout)")}
              checked={!config.events || config.events.form_open !== false}
              onChange={(value) => setEvent("form_open", value)}
            />
            <Checkbox
              label={t("pixels.event_purchase", "Order placed")}
              checked={!config.events || config.events.purchase !== false}
              onChange={(value) => setEvent("purchase", value)}
            />
          </InlineGrid>
          <ChoiceList
            title={t("pixels.purchase_event", "Send the order as")}
            choices={[
              { label: t("pixels.purchase_event_purchase", "Purchase"), value: "purchase" },
              {
                label: t("pixels.purchase_event_lead", "Lead"),
                value: "lead",
                helpText: t("pixels.purchase_event_lead_help", "Use this if you count a COD order as a sale only once it is delivered."),
              },
            ]}
            selected={[config.purchase_event || "purchase"]}
            onChange={(value) => setConfig("purchase_event", value[0])}
          />
          {info.hasTestCode && (
            <TextField
              label={t("pixels.test_event_code", "Test event code (optional)")}
              value={config.test_event_code || ""}
              onChange={(value) => setConfig("test_event_code", value.trim())}
              helpText={t("pixels.test_event_help", "Events are marked as tests while this is filled in. Clear it when you are done.")}
              autoComplete="off"
            />
          )}
          <Divider />
          <ChoiceList
            title={t("pixels.targeting_title", "Products")}
            choices={[
              { label: t("common.all_products", "All products"), value: "all" },
              { label: t("pixels.targeting_selected", "Only orders with selected products"), value: "selected", disabled: !p3Gate.allowed },
            ]}
            selected={[productTargeting ? "selected" : "all"]}
            onChange={(value) => set("targeting", { ...targeting, scope: value[0] })}
          />
          {productTargeting && (
            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
              <ResourceTargetPicker
                type="product"
                label={t("common.products", "Products")}
                ids={targeting.product_ids}
                onChange={(ids) => set("targeting", { ...targeting, product_ids: ids })}
              />
              <ResourceTargetPicker
                type="collection"
                label={t("common.collections", "Collections")}
                ids={targeting.collection_ids}
                onChange={(ids) => set("targeting", { ...targeting, collection_ids: ids })}
              />
            </InlineGrid>
          )}
          <Checkbox label={t("pixels.enabled", "Pixel is on")} checked={draft.enabled !== false} onChange={(value) => set("enabled", value)} />
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

export default PixelModal;
