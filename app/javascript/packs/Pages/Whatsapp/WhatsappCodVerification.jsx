import React, { useCallback, useContext, useMemo, useState } from "react";
import {
  Badge,
  Banner,
  BlockStack,
  Box,
  Button,
  Checkbox,
  InlineStack,
  Layout,
  Page,
  Text,
  TextField,
} from "@shopify/polaris";
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import { StoreContext } from "../../Context/Store";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import FeatureCallout from "../../Components/FeatureCallout";

const COD_VERIFICATION_WHATSAPP_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-17_at_2.13.14_PM_2.jpg?v=1791393035";
import { SectionCard, SettingGroup, SettingRow } from "../../Components/SettingsPrimitives";
import WhatsappCodVerificationPreview from "./WhatsappCodVerificationPreview";

/** The fields this screen owns, so dirty state is a comparison rather than a flag. */
const FIELDS = [
  "sendVerificationLinkOnly",
  "verificationTag",
  "autoVerify",
  "showCancelButton",
];

/**
 * WhatsApp COD verification.
 *
 * This used to be a row in the Default WhatsApp notification table with its
 * settings scattered across the general settings screen, so the feature had no
 * page of its own. It now follows the same shape as the other checkout widget
 * screens: a callout that explains it, its own activation card, then settings
 * with a live preview of what the customer actually opens.
 */
const WhatsappCodVerification = () => {
  const shopify = useAppBridge();
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    shop: [shop],
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);

  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState(false);
  const [banner, setBanner] = useState(null);

  const handleSettingChange = useCallback(
    (key) => (value) => {
      setSetting((prev) => ({ ...prev, [key]: value }));
      !contextualBar && setContextualBar(true);
    },
    [setSetting, contextualBar, setContextualBar]
  );

  const isDirty = useMemo(
    () => FIELDS.some((key) => setting?.[key] !== originalSetting?.[key]),
    [setting, originalSetting]
  );

  const handleDiscard = useCallback(() => {
    setSetting(originalSetting);
    setContextualBar(false);
  }, [originalSetting, setSetting, setContextualBar]);

  const handleSave = useCallback(async () => {
    setSaving(true);
    try {
      const res = await Api.post("/settings", { setting });
      setSetting(res.data);
      setOriginalSetting(res.data);
      setContextualBar(false);
      shopify?.toast?.show(I18n.t("admin.settings_saved"));
    } catch (_e) {
      shopify?.toast?.show(I18n.t("admin.settings_error"), { isError: true });
    } finally {
      setSaving(false);
    }
  }, [setting, setSetting, setOriginalSetting, setContextualBar, shopify]);

  // Sends the real template to the store owner's number, the same call the
  // Default WhatsApp table used to make from its Test button.
  const handleTest = useCallback(async () => {
    setTesting(true);
    setBanner(null);
    try {
      const res = await Api.post("/settings/test_notification", {
        type: "cod_verification",
        mode: "whatsapp",
        shop_id: shop?.id,
      });
      setBanner(
        res?.data?.success
          ? { tone: "success", text: I18n.t("admin.test_whatsapp_success") }
          : { tone: "critical", text: I18n.t("admin.something_went_wrong") }
      );
    } catch (_e) {
      setBanner({ tone: "critical", text: I18n.t("admin.something_went_wrong") });
    } finally {
      setTesting(false);
    }
  }, [shop?.id]);

  const enabled = setting?.sendVerificationLinkOnly === true;

  return (
    <Page
      title={I18n.t("admin.cod_verification_whatsapp")}
      subtitle={I18n.t("admin.cod_verification_whatsapp_description")}
      fullWidth={true}
    >
      <SaveBar id="whatsapp-cod-verification-save-bar" open={isDirty}>
        <button
          variant="primary"
          onClick={handleSave}
          loading={saving ? "" : undefined}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>{I18n.t("admin.discard")}</button>
      </SaveBar>

      <Layout>
        <Layout.Section variant="twoThirds">
          <BlockStack gap="400">
            <FeatureCallout
              illustration="widget"
              image={COD_VERIFICATION_WHATSAPP_CALLOUT_IMAGE}
              title={I18n.t("admin.cod_verification_whatsapp")}
              description={I18n.t("admin.cod_verification_whatsapp_description")}
              docsUrl="https://codking.tech/documentation/"
              showChat
              badge={
                enabled ? (
                  <Badge tone="success" progress="complete">
                    {I18n.t("pre_order.enabled")}
                  </Badge>
                ) : (
                  <Badge tone="attention" progress="incomplete">
                    {I18n.t("pre_order.inactive")}
                  </Badge>
                )
              }
            />

            {banner && (
              <Banner tone={banner.tone} onDismiss={() => setBanner(null)}>
                <Text as="p" variant="bodyMd">
                  {banner.text}
                </Text>
              </Banner>
            )}

            <SectionCard>
              <SettingGroup>
                <SettingRow
                  title={I18n.t("whatsapp_cod_verification.send_the_verification_link_on_whatsapp")}
                  description={I18n.t("whatsapp_cod_verification.cod_orders_get_a_whatsapp_message")}
                  control={
                    <Checkbox
                      label={I18n.t("whatsapp_cod_verification.send_the_verification_link_on_whatsapp")}
                      labelHidden
                      checked={enabled}
                      onChange={handleSettingChange("sendVerificationLinkOnly")}
                    />
                  }
                >
                  <InlineStack>
                    <Button onClick={handleTest} loading={testing}>
                      {I18n.t("admin.test_whatsapp")}
                    </Button>
                  </InlineStack>
                </SettingRow>
              </SettingGroup>
            </SectionCard>

            <SectionCard title={I18n.t("whatsapp_cod_verification.verification_settings")}>
              <SettingGroup>
                <TextField
                  label={I18n.t("admin.verification_tag_label")}
                  helpText={I18n.t("admin.verification_tag_help")}
                  value={setting?.verificationTag || ""}
                  onChange={handleSettingChange("verificationTag")}
                  autoComplete="off"
                />

                <Box paddingBlockStart="400">
                  <SettingRow
                    title={I18n.t("admin.auto_verify")}
                    description={I18n.t("admin.auto_verify_help")}
                    control={
                      <Checkbox
                        label={I18n.t("admin.auto_verify")}
                        labelHidden
                        checked={setting?.autoVerify || false}
                        onChange={handleSettingChange("autoVerify")}
                      />
                    }
                  />
                </Box>

                <Box paddingBlockStart="300">
                  <SettingRow
                    title={I18n.t("admin.show_cancel_button")}
                    description={I18n.t("admin.show_cancel_button_help")}
                    control={
                      <Checkbox
                        label={I18n.t("admin.show_cancel_button")}
                        labelHidden
                        checked={setting?.showCancelButton || false}
                        onChange={handleSettingChange("showCancelButton")}
                        disabled={setting?.autoVerify === true}
                      />
                    }
                  />
                </Box>

                {setting?.autoVerify === true && (
                  <Box paddingBlockStart="200">
                    <Text as="p" variant="bodySm" tone="subdued">
                      {I18n.t("whatsapp_cod_verification.auto_verify_confirms_the_order_as")}
                    </Text>
                  </Box>
                )}
              </SettingGroup>
            </SectionCard>
          </BlockStack>
        </Layout.Section>

        <Layout.Section variant="oneThird">
          {/* Sticky so the preview stays put while the settings scroll. */}
          <div style={{ position: "sticky", top: 16 }}>
            <BlockStack gap="200">
              <Text as="h3" variant="headingSm">
                {I18n.t("whatsapp_cod_verification.what_the_customer_opens")}
              </Text>
              <Text as="p" variant="bodySm" tone="subdued">
                {I18n.t("whatsapp_cod_verification.starts_at_the_whatsapp_message_tapping")}
              </Text>
              <WhatsappCodVerificationPreview
                autoVerify={setting?.autoVerify === true}
                showCancelButton={setting?.showCancelButton === true}
              />
            </BlockStack>
          </div>
        </Layout.Section>
      </Layout>
    </Page>
  );
};

export default WhatsappCodVerification;
