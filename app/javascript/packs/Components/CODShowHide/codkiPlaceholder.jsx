import React from "react";
import { Box, BlockStack, Text as PolarisText } from "@shopify/polaris";

const Placeholder = ({ children, isDisabled = false }) => (
  <div
    style={{
      maxWidth: "400px",
      padding: "16px",
      border: "1px dashed #C8C8CC",
      borderRadius: "8px",
      textAlign: "center",
      opacity: isDisabled ? 0.5 : 1,
    }}
  >
    <PolarisText as="span" variant="bodyMd" color="subdued">
      {children}
    </PolarisText>
  </div>
);

export default Placeholder;
