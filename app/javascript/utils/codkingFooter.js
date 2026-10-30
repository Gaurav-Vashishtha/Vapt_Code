import React from "react";
import { BlockStack, InlineStack, Text, Box } from "@shopify/polaris";
export default function CodKingFooter() {
  return (
    <Box paddingBlock="400" paddingInline="300">
      <BlockStack align="center" gap="200">
        <InlineStack align="center" gap="100">
          <Text as="p" variant="bodySm" tone="subdued">
            © COD King {new Date().getFullYear()}
          </Text>
        </InlineStack>
      </BlockStack>
    </Box>
  );
}
