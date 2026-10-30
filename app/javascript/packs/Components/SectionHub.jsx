import React, { useState } from "react";
import {
  Page,
  Layout,
  Card,
  Text,
  Badge,
  Icon,
  Link,
  Button,
  BlockStack,
  InlineGrid,
  Box,
  InlineStack,
} from "@shopify/polaris";
import { CircleTickMajor, CircleMinusMajor } from "@shopify/polaris-icons";
import I18n from "../i18n-lang";

export const hubNavigate = (e, path, extraQuery = {}) => {
  if (e) e.preventDefault();
  const params = new URLSearchParams(window.location.search || "");
  Object.entries(extraQuery).forEach(([k, v]) => {
    if (v != null && v !== "") params.set(k, String(v));
  });
  const qs = params.toString();
  const href = qs ? `${path}?${qs}` : path;
  window.history.pushState({}, "", href);
  window.dispatchEvent(new PopStateEvent("popstate"));
};

function FeatureToggle({ item }) {
  const [saving, setSaving] = useState(false);
  const handleClick = async () => {
    if (saving) return;
    setSaving(true);
    try {
      await item.onToggle(!item.enabled);
    } finally {
      setSaving(false);
    }
  };
  return (
    <Button
      size="slim"
      loading={saving}
      pressed={!!item.enabled}
      onClick={handleClick}
    >
      {item.enabled
        ? I18n.t("admin.turn_off", { defaultValue: "Turn off" })
        : I18n.t("admin.turn_on", { defaultValue: "Turn on" })}
    </Button>
  );
}

function HubTile({ item }) {
  const statusTone = item.enabled ? "success" : "attention";
  return (
    <Box
      padding="400"
      background="bg-surface-secondary"
      borderRadius="300"
      minHeight="100%"
    >
      <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
        <InlineStack gap="200" align="start" blockAlign="start" wrap={false}>
          {!item.noStatus && (
            <Box>
              <Icon
                source={item.enabled ? CircleTickMajor : CircleMinusMajor}
                tone={statusTone}
              />
            </Box>
          )}
          <BlockStack gap="100">
            <InlineStack gap="150" wrap blockAlign="center">
              <Text variant="bodyMd" fontWeight="semibold" as="span">
                {item.title}
              </Text>
              {item.isNew && (
                <Badge tone="info" size="small">
                  {I18n.t("admin.new", { defaultValue: "New" })}
                </Badge>
              )}
            </InlineStack>
            <Text variant="bodySm" tone="subdued" as="p">
              {item.description}
            </Text>
          </BlockStack>
        </InlineStack>

        <div style={{ marginTop: "auto", paddingTop: 12 }}>
          <InlineStack
            align={item.noStatus && !item.onToggle ? "end" : "space-between"}
            blockAlign="center"
            wrap={false}
            gap="200"
          >
            {item.onToggle ? (
              <FeatureToggle item={item} />
            ) : (
              !item.noStatus && (
                <Badge
                  tone={statusTone}
                  progress={item.enabled ? "complete" : "incomplete"}
                >
                  {item.enabled
                    ? I18n.t("admin.enabled", { defaultValue: "Enabled" })
                    : I18n.t("admin.disabled", { defaultValue: "Disabled" })}
                </Badge>
              )
            )}
            {item.href && (
              <Link url={item.href} onClick={(e) => hubNavigate(e, item.href)}>
                {I18n.t("admin.manage", { defaultValue: "Manage" })}
              </Link>
            )}
          </InlineStack>
        </div>
      </div>
    </Box>
  );
}

const SectionHub = ({
  title,
  subtitle,
  items = [],
  preview = null,
  backAction = { content: I18n.t("admin.back_to_summary", { defaultValue: "Back" }), href: "/" },
  columns = { xs: 1, sm: 2, lg: 2 },
}) => {
  return (
    <Page
      title={title}
      subtitle={subtitle}
      compactTitle
      backAction={{
        content: backAction.content,
        onAction: (e) => hubNavigate(e, backAction.href || "/"),
      }}
    >
      <Layout>
        <Layout.Section variant={preview ? "oneHalf" : "fullWidth"}>
          <Card padding="0">
            <Box padding={{ xs: "400", sm: "500" }}>
              <InlineGrid
                columns={items.length === 1 ? 1 : preview ? { xs: 1, sm: 1, lg: 2 } : columns}
                gap="300"
              >
                {items.map((item, idx) => (
                  <HubTile key={idx} item={item} />
                ))}
              </InlineGrid>
            </Box>
          </Card>
        </Layout.Section>
        {preview && (
          <Layout.Section variant="oneHalf">{preview}</Layout.Section>
        )}
      </Layout>
    </Page>
  );
};

export default SectionHub;
