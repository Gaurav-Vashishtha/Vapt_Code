import React from "react";
import { Icon, TextField, BlockStack, Text as PolarisText } from "@shopify/polaris";
import { QuestionMarkMajor } from "@shopify/polaris-icons";
import MultiSelect from "./codkiMultiSelect";

// Shared utility functions for COD Show/Hide components
export const renderTooltip = (content) => (
  <></>
  // <Tooltip content={content}>
  //   <Icon source={QuestionMarkMajor} tone="subdued" />
  // </Tooltip>
);

// Factory function to create renderTextField
// Signature: (label, value, onChange, helpText, placeholder, example, rows, disabled, width, hideIf)
export const createRenderTextField = (defaultDisabled = false) => {
  return (
    label,
    value,
    onChange,
    helpText,
    placeholder,
    example = "",
    rows = 1,
    isDisabled = false,
    width = "100%",
    hideIf = false
  ) => {
    if (hideIf) return null;
    
    return (
      <BlockStack gap="200">
        <TextField
          label={label}
          value={value || ""}
          onChange={onChange}
          helpText={helpText}
          placeholder={placeholder}
          disabled={defaultDisabled || isDisabled}
          multiline={rows > 1}
          rows={rows}
          autoComplete="off"
        />
        {example && example !== "" && (
          <PolarisText variant="bodySm" tone="subdued">
            {example}
          </PolarisText>
        )}
      </BlockStack>
    );
  };
};

// Factory function to create renderMultiSelect
export const createRenderMultiSelect = (setting, handleSettingChange, disabled = false) => {
  return (
    key,
    label,
    options = [],
    helpText = "",
    isDisabled = false,
    width = "100%",
    hideIf = false
  ) => {
    if (hideIf) return null;
    
    const currentValue = setting[key] || "";
    const selected = currentValue ? currentValue.split(",").filter(Boolean) : [];
    
    return (
      <BlockStack gap="200">
        <MultiSelect
          label={label}
          options={options}
          selected={selected}
          onChange={(newSelected) => {
            handleSettingChange(key)(newSelected.join(","));
          }}
          disabled={disabled || isDisabled}
        />
        {helpText && (
          <PolarisText variant="bodySm" tone="subdued">
            {helpText}
          </PolarisText>
        )}
      </BlockStack>
    );
  };
};
