import React, { useCallback, useContext, useEffect, useState } from "react";
import {
  Layout,
  Card,
  BlockStack,
  Text,
  Button,
  Checkbox,
  Banner,
  Box,
  List,
  InlineStack,
  SkeletonBodyText,
} from "@shopify/polaris";
import { ExternalMinor } from "@shopify/polaris-icons";
import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";
import I18n from "../i18n-lang";
import FeatureCallout from "./FeatureCallout";
import PlusCheckoutOtpPreview from "./PlusCheckoutOtpPreview";

// Shown in the callout panel at 290x210.
const PLUS_WIDGET_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-17_at_2.13.13_PM.jpg?v=1791392831";

/** UI copy: `admin.plus_checkout_*` in `config/localeJson/<locale>.json` (sync from `en.json`). */

const truthy = (v) =>
  v === true || v === "true" || v === 1 || v === "1";

const PlusCheckoutOtpExtensionSettings = () => {
  const {
    contextualBar: [, setContextualBar],
    setting: [setting, setSetting],
  } = useContext(StoreContext);

  const [editorUrl, setEditorUrl] = useState("");
  const [editorLoading, setEditorLoading] = useState(true);
  const [editorError, setEditorError] = useState(null);

  const enabled = truthy(
    setting?.plusCheckoutOtpExtensionEnabled ??
      setting?.plus_checkout_otp_extension_enabled,
  );

  const fetchEditorLink = useCallback(async () => {
    setEditorLoading(true);
    setEditorError(null);
    try {
      const res = await Api.get(
        `https://${process.env.APP_HOST}/settings/checkout_extension_editor_link`,
      );
      if (res.data?.url) {
        setEditorUrl(res.data.url);
      } else {
        setEditorError("unavailable");
      }
    } catch (_e) {
      setEditorError("unavailable");
    } finally {
      setEditorLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchEditorLink();
  }, [fetchEditorLink]);

  const handleToggle = useCallback(
    (checked) => {
      setSetting((prev) => ({
        ...prev,
        plusCheckoutOtpExtensionEnabled: checked,
      }));
      setContextualBar(true);
    },
    [setSetting, setContextualBar],
  );

  return (
    <Layout>
      <Layout.Section variant="twoThirds">
        <BlockStack gap="400">
          <FeatureCallout
            illustration="widget"
            image={PLUS_WIDGET_CALLOUT_IMAGE}
            title={I18n.t("admin.plus_checkout_title", {
              defaultValue: "Checkout extension OTP",
            })}
            description={I18n.t("admin.plus_checkout_callout_description", {
              defaultValue:
                "OTP verification on the Shopify Native Checkout, when customer selects Cash on delivery Payment method.",
            })}
            showChat
          />
          {editorError && (
            <Banner tone="warning" title={I18n.t("admin.plus_checkout_editor_unavailable_title")}>
              <p>{I18n.t("admin.plus_checkout_editor_unavailable_body")}</p>
            </Banner>
          )}

          <Card>
            <BlockStack gap="400">
              <Text variant="headingMd" as="h2">
                {I18n.t("admin.plus_checkout_extension_page_title")}
              </Text>
              <Text as="p" variant="bodyMd" tone="subdued">
                {I18n.t("admin.plus_checkout_extension_page_subtitle")}
              </Text>

              <Checkbox
                label={I18n.t("admin.plus_checkout_extension_toggle")}
                helpText={I18n.t("admin.plus_checkout_extension_toggle_help")}
                checked={enabled}
                onChange={handleToggle}
              />

              <Box paddingBlockStart="200">
                <Text variant="headingSm" as="h3">
                  {I18n.t("admin.plus_checkout_extension_steps_title")}
                </Text>
              </Box>
              <List type="number">
                <List.Item>
                  {I18n.t("admin.plus_checkout_extension_step_1")}
                </List.Item>
                <List.Item>
                  {I18n.t("admin.plus_checkout_extension_step_2")}
                </List.Item>
                <List.Item>
                  {I18n.t("admin.plus_checkout_extension_step_3")}
                </List.Item>
                <List.Item>
                  {I18n.t("admin.plus_checkout_extension_step_4")}
                </List.Item>
              </List>

              <InlineStack gap="300" blockAlign="center">
                {editorLoading ? (
                  <SkeletonBodyText lines={1} />
                ) : editorUrl ? (
                  <Button
                    variant="primary"
                    icon={ExternalMinor}
                    url={editorUrl}
                    target="_blank"
                  >
                    {I18n.t("admin.plus_checkout_open_editor")}
                  </Button>
                ) : null}
              </InlineStack>
            </BlockStack>
          </Card>
        </BlockStack>
      </Layout.Section>

      <Layout.Section variant="oneThird">
        {/* Not sticky: the preview is a whole checkout page and is taller than
            the viewport, so pinning it only meant it never moved past Contact. */}
        <div>
          <BlockStack gap="200">
            <Text as="h3" variant="headingSm">
              {I18n.t("plus_checkout_otp_extension_settings.how_it_looks_in_checkout")}
            </Text>
            <Text as="p" variant="bodySm" tone="subdued">
              {I18n.t("plus_checkout_otp_extension_settings.the_buttons_work_here_use_1234")}
            </Text>
            <PlusCheckoutOtpPreview />
          </BlockStack>
        </div>
      </Layout.Section>
    </Layout>
  );
};

export default PlusCheckoutOtpExtensionSettings;
