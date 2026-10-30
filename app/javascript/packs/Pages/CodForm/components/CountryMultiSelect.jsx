import React, { useMemo, useState } from "react";
import { Autocomplete, BlockStack, InlineStack, Tag, Text } from "@shopify/polaris";
import { COUNTRIES, countryName } from "../constants";
import { t } from "../i18n";

/** Searchable multi-select of ISO-2 country codes, selected ones as tags. */
const CountryMultiSelect = ({ label, value, onChange, helpText, emptyText, disabled, allowedCodes }) => {
  const selected = Array.isArray(value) ? value : [];
  const [query, setQuery] = useState("");

  const all = useMemo(
    () =>
      COUNTRIES.filter((country) => !allowedCodes || allowedCodes.includes(country.value)).map((country) => ({
        value: country.value,
        label: country.label,
      })),
    [allowedCodes],
  );

  const options = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const list = needle
      ? all.filter(
          (option) => option.label.toLowerCase().includes(needle) || option.value.toLowerCase() === needle,
        )
      : all;
    return list.slice(0, 60);
  }, [all, query]);

  return (
    <BlockStack gap="200">
      <Autocomplete
        allowMultiple
        options={options}
        selected={selected}
        onSelect={onChange}
        textField={
          <Autocomplete.TextField
            label={label}
            value={query}
            onChange={setQuery}
            autoComplete="off"
            disabled={disabled}
            helpText={helpText}
            placeholder={t("common.search_countries", "Search countries")}
          />
        }
      />
      {selected.length > 0 ? (
        <InlineStack gap="200" wrap>
          {selected.map((code) => (
            <Tag
              key={code}
              disabled={disabled}
              onRemove={() => onChange(selected.filter((item) => item !== code))}
            >
              {countryName(code)}
            </Tag>
          ))}
        </InlineStack>
      ) : emptyText ? (
        <Text as="p" variant="bodySm" tone="subdued">
          {emptyText}
        </Text>
      ) : null}
    </BlockStack>
  );
};

export default CountryMultiSelect;
