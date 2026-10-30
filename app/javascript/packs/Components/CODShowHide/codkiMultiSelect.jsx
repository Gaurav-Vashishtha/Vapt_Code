import React, { useState, useCallback, useEffect } from "react";
import {
  Button,
  Popover,
  Box,
  BlockStack,
  TextField,
  Icon,
  ActionList,
  Badge,
  InlineStack,
  Text as PolarisText,
} from "@shopify/polaris";
import { SearchMinor } from "@shopify/polaris-icons";
import I18n from "../../i18n-lang";

const normalizeSelection = (values = [], options = []) => {
  if (!Array.isArray(values)) return [];
  const optionSet = new Set(options.map((option) => option.value));
  return values.filter((value) => optionSet.has(value));
};

const arraysEqual = (first = [], second = []) =>
  first.length === second.length &&
  first.every((value, index) => value === second[index]);

// Enhanced MultiSelect component with search functionality
function MultiSelect({ label, options = [], selected, onChange, disabled }) {
  const [popoverActive, setPopoverActive] = useState(false);
  const [searchValue, setSearchValue] = useState("");
  const [selectedOptions, setSelectedOptions] = useState(() =>
    normalizeSelection(selected, options)
  );

  useEffect(() => {
    const sanitizedSelection = normalizeSelection(selected, options);
    setSelectedOptions((current) =>
      arraysEqual(current, sanitizedSelection) ? current : sanitizedSelection
    );
  }, [selected, options]);

  const handleSearchChange = useCallback((value) => {
    setSearchValue(value);
  }, []);

  const toggleOption = useCallback(
    (optionValue) => {
      if (disabled) return;
      const newSelected = selectedOptions.includes(optionValue)
        ? selectedOptions.filter((value) => value !== optionValue)
        : [...selectedOptions, optionValue];
      setSelectedOptions(newSelected);
      onChange(newSelected);
    },
    [selectedOptions, onChange, disabled]
  );

  const filteredOptions = options.filter((option) =>
    option.label.toLowerCase().includes(searchValue.toLowerCase())
  );

  const activator = (
    <Button
      onClick={() => !disabled && setPopoverActive((prev) => !prev)}
      disclosure
      fullWidth
      textAlign="left"
      disabled={disabled}
    >
      <InlineStack align="space-between" blockAlign="center" width="100%">
        <PolarisText variant="bodyMd" tone="subdued">
          {label}
        </PolarisText>
        &nbsp;{" "}
        <Badge tone="success">
          {I18n.t("cod_show_hide_detail.items_selected", {
            count: selectedOptions.length,
          })}
        </Badge>
      </InlineStack>
    </Button>
  );

  return (
    <Popover
      active={popoverActive && !disabled}
      activator={activator}
      onClose={() => setPopoverActive(false)}
      fullWidth
      preferredAlignment="left"
    >
      <Popover.Pane>
        <Box padding="400" width="320px">
          <BlockStack gap="300">
            <TextField
              labelHidden
              placeholder={I18n.t("cod_show_hide_detail.search_options")}
              value={searchValue}
              onChange={handleSearchChange}
              prefix={<Icon source={SearchMinor} />}
              clearButton
              onClearButtonClick={() => setSearchValue("")}
              autoComplete="off"
            />
            <Box
              style={{
                maxHeight: "240px",
                overflowY: "auto",
                border: "1px solid #DCDCDC",
                borderRadius: "8px",
              }}
              padding="200"
              background="bg-surface"
            >
              <ActionList
                actionRole="menuitemcheckbox"
                items={filteredOptions.map((option) => ({
                  content: option.label,
                  onAction: () => toggleOption(option.value),
                  active: selectedOptions.includes(option.value),
                }))}
              />
            </Box>
          </BlockStack>
        </Box>
      </Popover.Pane>
    </Popover>
  );
}

export default MultiSelect;
