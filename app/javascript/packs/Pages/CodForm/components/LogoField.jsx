import React, { useEffect, useState } from "react";
import { BlockStack, Button, InlineStack, Text, TextField, Thumbnail } from "@shopify/polaris";
import { t } from "../i18n";

/**
 * Header logo of the form (design.header.logo_url): a link to an image that is already online
 * (for example Shopify admin → Content → Files → copy link). Shows a preview of the link, and
 * says so when the image cannot be loaded.
 */
const LogoField = ({ value, onChange }) => {
  const url = value || "";
  const invalid = !!url && !/^https:\/\//i.test(url);
  const [broken, setBroken] = useState(false);

  useEffect(() => setBroken(false), [url]);

  const error = invalid
    ? t("designer.https_required", "Use a link that starts with https://")
    : broken
      ? t("designer.logo_broken", "This link does not open an image. Check that it points to an image file.")
      : undefined;

  return (
    <BlockStack gap="200">
      <TextField
        label={t("designer.design_logo", "Logo URL (optional)")}
        value={url}
        onChange={(text) => onChange(text.trim())}
        error={error}
        placeholder="https://cdn.shopify.com/s/files/…/logo.png"
        helpText={t(
          "designer.logo_help",
          "Shown at the top of the form. Upload your logo in Shopify admin → Content → Files, copy its link and paste it here. A wide logo about 260×60 px looks best.",
        )}
        autoComplete="off"
        clearButton
        onClearButtonClick={() => onChange("")}
      />
      {url && !invalid && !broken && (
        <InlineStack gap="300" blockAlign="center">
          <Thumbnail source={url} alt={t("designer.logo_preview", "Logo preview")} size="large" />
          <BlockStack gap="100">
            <Text as="p" variant="bodySm" tone="subdued">
              {t("designer.logo_preview", "Logo preview")}
            </Text>
            <Button size="slim" tone="critical" variant="plain" onClick={() => onChange("")}>
              {t("designer.logo_remove", "Remove")}
            </Button>
          </BlockStack>
          {/* Hidden probe: Thumbnail has no onError, so a broken link is detected here. */}
          <img src={url} alt="" style={{ display: "none" }} onError={() => setBroken(true)} />
        </InlineStack>
      )}
    </BlockStack>
  );
};

export default LogoField;
