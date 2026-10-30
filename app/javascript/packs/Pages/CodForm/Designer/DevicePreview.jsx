import React, { useState } from "react";
import styled from "styled-components";
import { BlockStack, Button, ButtonGroup, Card, InlineStack, Select, Text } from "@shopify/polaris";
import { MobileMajor, DesktopMajor } from "@shopify/polaris-icons";
import FormMock from "../components/FormMock";
import PreviewFrame from "../components/PreviewFrame";
import { localeName } from "../constants";
import { t } from "../i18n";

const Stage = styled.div`
  background: #6b7280;
  background-image: linear-gradient(135deg, #7c8494, #5b6270);
  border-radius: 12px;
  padding: ${(p) => (p.$mobile ? "24px 12px 0" : "24px 16px")};
  display: flex;
  justify-content: center;
  align-items: ${(p) => (p.$mobile ? "flex-end" : "center")};
  min-height: 420px;
  max-height: 78vh;
  overflow: auto;
`;

const Frame = styled.div`
  width: 100%;
  max-width: ${(p) => (p.$mobile ? "375px" : "520px")};
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.28);
  border-radius: ${(p) => (p.$mobile ? "16px 16px 0 0" : "12px")};
  overflow: hidden;
`;

/**
 * Live desktop / mobile preview of the draft (FRM-11). The default renderer
 * is the React mock; when the extension asset base is known the real form
 * bundle can be shown instead through PreviewFrame (H.6).
 */
const DevicePreview = ({ config, defaultsTexts, locale, locales, onLocaleChange, bootstrap, buttonConfig, storefrontPreviewUrl, initialView = "form" }) => {
  const [device, setDevice] = useState("mobile");
  const [view, setView] = useState(initialView);
  // The real storefront form is the default whenever it can be shown; the mock is the fallback.
  const [chosenEngine, setEngine] = useState(null);
  const [frameFailed, setFrameFailed] = useState(false);
  const preview = (bootstrap && bootstrap.preview) || {};
  const exactAvailable = !!(preview.assetBase && preview.frameUrl) && !frameFailed;
  const engine = chosenEngine || (exactAvailable ? "exact" : "mock");
  const mobile = device === "mobile";

  return (
    <Card>
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center" gap="200" wrap>
          <Text as="h2" variant="headingMd">
            {t("common.preview", "Preview")}
          </Text>
          <ButtonGroup variant="segmented">
            <Button icon={MobileMajor} pressed={mobile} onClick={() => setDevice("mobile")}>
              {t("common.mobile", "Mobile")}
            </Button>
            <Button icon={DesktopMajor} pressed={!mobile} onClick={() => setDevice("desktop")}>
              {t("common.desktop", "Desktop")}
            </Button>
          </ButtonGroup>
        </InlineStack>
        <InlineStack gap="300" wrap>
          <div style={{ flex: "1 1 140px" }}>
            <Select
              label={t("designer.preview_view", "Step")}
              options={[
                { value: "form", label: t("designer.preview_view_form", "Form") },
                { value: "otp", label: t("designer.preview_view_otp", "OTP") },
                { value: "thankyou", label: t("designer.preview_view_thank_you", "Thank-you") },
              ]}
              value={view}
              onChange={setView}
            />
          </div>
          <div style={{ flex: "1 1 140px" }}>
            <Select
              label={t("designer.texts_locale", "Language")}
              options={(locales || ["en"]).map((code) => ({ value: code, label: localeName(code) }))}
              value={locale}
              onChange={onLocaleChange}
            />
          </div>
          {exactAvailable && (
            <div style={{ flex: "1 1 140px" }}>
              <Select
                label={t("designer.preview_engine", "Renderer")}
                options={[
                  { value: "mock", label: t("designer.preview_engine_mock", "Quick preview") },
                  { value: "exact", label: t("designer.preview_engine_exact", "Storefront form") },
                ]}
                value={engine}
                onChange={setEngine}
              />
            </div>
          )}
        </InlineStack>
        <Stage $mobile={mobile}>
          <Frame $mobile={mobile}>
            {engine === "exact" && exactAvailable ? (
              <PreviewFrame
                frameUrl={preview.frameUrl}
                assetBase={preview.assetBase}
                form={config}
                button={buttonConfig}
                texts={defaultsTexts}
                locale={locale}
                device={device}
                view={view}
                onError={() => {
                  setFrameFailed(true);
                  setEngine("mock");
                }}
              />
            ) : (
              <FormMock
                config={config}
                defaultsTexts={defaultsTexts}
                locale={locale}
                device={device}
                view={view}
                moneyFormat={bootstrap && bootstrap.moneyFormat}
                currency={bootstrap && bootstrap.currency}
                shopCountry={bootstrap && bootstrap.shopCountry}
                hidePoweredBy={false}
              />
            )}
          </Frame>
        </Stage>
        <InlineStack align="space-between" blockAlign="center" gap="200" wrap>
          <Text as="p" variant="bodySm" tone="subdued">
            {t("designer.preview_note", "A preview with sample products and prices. It shows your draft, not what is live.")}
          </Text>
          {storefrontPreviewUrl && (
            <Button variant="plain" url={storefrontPreviewUrl} external target="_blank">
              {t("designer.open_storefront_preview", "Open storefront preview")}
            </Button>
          )}
        </InlineStack>
      </BlockStack>
    </Card>
  );
};

export default DevicePreview;
