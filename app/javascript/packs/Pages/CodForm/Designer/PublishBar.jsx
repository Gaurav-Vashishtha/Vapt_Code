import React from "react";
import { Card, InlineStack, BlockStack, Text, Badge, Button } from "@shopify/polaris";
import { formatDateTime } from "../utils";
import { t } from "../i18n";

/**
 * Draft / publish state (FRM-11). The storefront reads only the published
 * version; the save bar stores the draft, this bar publishes or discards it.
 */
const PublishBar = ({ publishedAt, publishedVersion, hasUnpublished, isDirty, publishing, discarding, onPublish, onDiscardDraft }) => {
  const never = !publishedVersion;
  return (
    <Card>
      <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
        <BlockStack gap="100">
          <InlineStack gap="200" blockAlign="center">
            {never ? (
              <Badge tone="attention">{t("designer.not_published", "Not published yet")}</Badge>
            ) : hasUnpublished || isDirty ? (
              <Badge tone="attention">{t("designer.unpublished_changes", "Unpublished changes")}</Badge>
            ) : (
              <Badge tone="success">{t("designer.published", "Published")}</Badge>
            )}
            {!never && publishedAt && (
              <Text as="span" variant="bodySm" tone="subdued">
                {t("designer.published_at", "Last published %{date}", { date: formatDateTime(publishedAt) })}
              </Text>
            )}
          </InlineStack>
          <Text as="p" variant="bodySm" tone="subdued">
            {t("designer.publish_help_live", "Saving publishes the form to your store. If a setting needs fixing, it stays a draft until it is fixed.")}
          </Text>
        </BlockStack>
        <InlineStack gap="200">
          <Button onClick={onDiscardDraft} loading={discarding} disabled={never || (!hasUnpublished && !isDirty) || publishing}>
            {t("common.discard_draft", "Discard draft")}
          </Button>
          <Button variant="primary" onClick={onPublish} loading={publishing} disabled={(!hasUnpublished && !isDirty && !never) || discarding}>
            {isDirty ? t("designer.save_and_publish", "Save and publish") : t("common.publish", "Publish")}
          </Button>
        </InlineStack>
      </InlineStack>
    </Card>
  );
};

export default PublishBar;
