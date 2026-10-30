import React from "react";
import { BlockStack, Card, InlineStack, Text } from "@shopify/polaris";

const SectionCard = ({ title, description, children }) => (
  <Card padding="600">
    <BlockStack gap="400">
      {(title || description) && (
        <BlockStack gap="100">
          {title && (
            <Text variant="headingMd" as="h3">
              {title}
            </Text>
          )}
          {description && (
            <Text variant="bodyMd" tone="subdued" as="p">
              {description}
            </Text>
          )}
        </BlockStack>
      )}
      {children}
    </BlockStack>
  </Card>
);

/* A setting reads as a sentence with its control at the end of the line:
   bold name, one plain line under it, switch on the right. */
const SettingRow = ({ title, description, control, children }) => (
  <BlockStack gap="200">
    <InlineStack align="space-between" blockAlign="start" gap="400" wrap={false}>
      <BlockStack gap="050">
        <Text variant="headingSm" as="h4">
          {title}
        </Text>
        {description && (
          <Text variant="bodySm" tone="subdued" as="p">
            {description}
          </Text>
        )}
      </BlockStack>
      {control}
    </InlineStack>
    {children}
  </BlockStack>
);

/* Groups of settings inside one card, separated the way the reference does it. */
const SettingGroup = ({ title, children }) => (
  <BlockStack gap="300">
    {title && (
      <Text variant="headingMd" as="h3">
        {title}
      </Text>
    )}
    {children}
  </BlockStack>
);

export { SectionCard, SettingRow, SettingGroup };
