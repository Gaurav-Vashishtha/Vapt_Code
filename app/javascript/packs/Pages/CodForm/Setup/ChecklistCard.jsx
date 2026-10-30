import React from "react";
import { Card, BlockStack, InlineStack, Text, Button, Icon, ProgressBar } from "@shopify/polaris";
import { CircleTickMajor, CircleDisabledMajor } from "@shopify/polaris-icons";
import { navigateTo } from "../../../../utils/navigate";
import { PATHS } from "../constants";
import { t } from "../i18n";

/** Setup checklist (DSH-6): embed, preset, shipping rate. (The test-order step is no longer shown.) */
const ChecklistCard = ({ checklist, themeEditorUrl }) => {
  const items = Array.isArray(checklist) ? checklist : [];
  const meta = {
    embed: {
      label: t("setup.check_embed", "Turn on the COD Form app embed"),
      cta: t("setup.check_embed_cta", "Open theme editor"),
      url: themeEditorUrl,
    },
    preset: {
      label: t("setup.check_preset", "Choose your button preset"),
      cta: t("setup.check_preset_cta", "Open Buttons"),
      path: PATHS.buttons,
    },
    shipping_rate: {
      label: t("setup.check_shipping", "Add a shipping rate"),
      cta: t("setup.check_shipping_cta", "Open Shipping rates"),
      path: PATHS.shipping,
    },
  };
  const known = items.filter((item) => meta[item.key]);
  if (known.length === 0) return null;
  const done = known.filter((item) => item.done).length;

  return (
    <Card>
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center">
          <Text as="h2" variant="headingMd">
            {t("setup.checklist_title", "Setup checklist")}
          </Text>
          <Text as="span" variant="bodySm" tone="subdued">
            {t("setup.checklist_progress", "%{done} of %{total} done", { done, total: known.length })}
          </Text>
        </InlineStack>
        <ProgressBar progress={(done / known.length) * 100} size="small" tone="primary" />
        <BlockStack gap="200">
          {known.map((item) => {
            const entry = meta[item.key];
            return (
              <InlineStack key={item.key} align="space-between" blockAlign="center" gap="300" wrap={false}>
                <InlineStack gap="200" blockAlign="center" wrap={false}>
                  <span style={{ display: "inline-flex", flex: "0 0 auto" }}>
                    <Icon source={item.done ? CircleTickMajor : CircleDisabledMajor} tone={item.done ? "success" : "subdued"} />
                  </span>
                  <Text as="span" variant="bodyMd" tone={item.done ? "subdued" : undefined}>
                    {entry.label}
                  </Text>
                </InlineStack>
                {!item.done &&
                  (entry.url ? (
                    <Button size="slim" url={entry.url} external target="_blank">
                      {entry.cta}
                    </Button>
                  ) : (
                    <Button
                      size="slim"
                      onClick={() => navigateTo(entry.path)}
                    >
                      {entry.cta}
                    </Button>
                  ))}
              </InlineStack>
            );
          })}
        </BlockStack>
      </BlockStack>
    </Card>
  );
};

export default ChecklistCard;
