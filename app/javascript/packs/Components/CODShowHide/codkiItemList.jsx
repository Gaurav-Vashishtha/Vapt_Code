import React from "react";
import { BlockStack, Text as PolarisText, Button } from "@shopify/polaris";
import { CancelSmallMinor } from "@shopify/polaris-icons";

function ItemList({ items, onRemove, disabled = false }) {
  return (
    <div style={{ maxHeight: "200px", maxWidth: "400px", overflowY: "scroll" }}>
      <BlockStack gap="1">
        {items.map((item) => (
          <div key={item} style={{ width: "100%" }}>
            <div
              style={{
                width: "100%",
                display: "flex",
                background: "#F6F6F7",
                borderRadius: "6px",
                padding: "6px 8px",
                alignItems: "center",
                justifyContent: "space-between",
                opacity: disabled ? 0.5 : 1,
              }}
            >
              <PolarisText as="span" variant="bodyMd" style={{ flexGrow: 1 }}>
                {item}
              </PolarisText>
              <Button
                onClick={() => !disabled && onRemove(item)}
                plain
                icon={CancelSmallMinor}
                accessibilityLabel={`Remove ${item}`}
                disabled={disabled}
              />
            </div>
          </div>
        ))}
      </BlockStack>
    </div>
  );
}

export default ItemList;
