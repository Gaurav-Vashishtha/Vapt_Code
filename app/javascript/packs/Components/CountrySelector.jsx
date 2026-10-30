import React, { useState, useMemo, useCallback } from "react";
import {
  TextField,
  Popover,
  Text,
  Box,
  Select,
} from "@shopify/polaris";
import I18n from "../i18n-lang";

// All countries list (including India)
const allCountries = [
  { code: "IN", name: "India" },
  { code: "US", name: "United States" },
  { code: "GB", name: "United Kingdom" },
  { code: "CA", name: "Canada" },
  { code: "AU", name: "Australia" },
  { code: "DE", name: "Germany" },
  { code: "FR", name: "France" },
  { code: "IT", name: "Italy" },
  { code: "ES", name: "Spain" },
  { code: "NL", name: "Netherlands" },
  { code: "BE", name: "Belgium" },
  { code: "AT", name: "Austria" },
  { code: "CH", name: "Switzerland" },
  { code: "SE", name: "Sweden" },
  { code: "NO", name: "Norway" },
  { code: "DK", name: "Denmark" },
  { code: "FI", name: "Finland" },
  { code: "IE", name: "Ireland" },
  { code: "PT", name: "Portugal" },
  { code: "GR", name: "Greece" },
  { code: "PL", name: "Poland" },
  { code: "CZ", name: "Czech Republic" },
  { code: "HU", name: "Hungary" },
  { code: "SK", name: "Slovakia" },
  { code: "SI", name: "Slovenia" },
  { code: "HR", name: "Croatia" },
  { code: "BG", name: "Bulgaria" },
  { code: "RO", name: "Romania" },
  { code: "EE", name: "Estonia" },
  { code: "LV", name: "Latvia" },
  { code: "LT", name: "Lithuania" },
  { code: "LU", name: "Luxembourg" },
  { code: "MT", name: "Malta" },
  { code: "CY", name: "Cyprus" },
  { code: "JP", name: "Japan" },
  { code: "KR", name: "South Korea" },
  { code: "SG", name: "Singapore" },
  { code: "HK", name: "Hong Kong" },
  { code: "MY", name: "Malaysia" },
  { code: "TH", name: "Thailand" },
  { code: "PH", name: "Philippines" },
  { code: "ID", name: "Indonesia" },
  { code: "VN", name: "Vietnam" },
  { code: "BD", name: "Bangladesh" },
  { code: "PK", name: "Pakistan" },
  { code: "LK", name: "Sri Lanka" },
  { code: "NP", name: "Nepal" },
  { code: "AE", name: "UAE" },
  { code: "SA", name: "Saudi Arabia" },
  { code: "QA", name: "Qatar" },
  { code: "KW", name: "Kuwait" },
  { code: "BH", name: "Bahrain" },
  { code: "OM", name: "Oman" },
  { code: "JO", name: "Jordan" },
  { code: "LB", name: "Lebanon" },
  { code: "EG", name: "Egypt" },
  { code: "ZA", name: "South Africa" },
  { code: "NG", name: "Nigeria" },
  { code: "KE", name: "Kenya" },
  { code: "GH", name: "Ghana" },
  { code: "UG", name: "Uganda" },
  { code: "TZ", name: "Tanzania" },
  { code: "ZW", name: "Zimbabwe" },
  { code: "BW", name: "Botswana" },
  { code: "ZM", name: "Zambia" },
  { code: "MX", name: "Mexico" },
  { code: "BR", name: "Brazil" },
  { code: "AR", name: "Argentina" },
  { code: "CL", name: "Chile" },
  { code: "CO", name: "Colombia" },
  { code: "PE", name: "Peru" },
  { code: "VE", name: "Venezuela" },
  { code: "UY", name: "Uruguay" },
  { code: "PY", name: "Paraguay" },
  { code: "BO", name: "Bolivia" },
  { code: "EC", name: "Ecuador" },
  { code: "GT", name: "Guatemala" },
  { code: "HN", name: "Honduras" },
  { code: "SV", name: "El Salvador" },
  { code: "NI", name: "Nicaragua" },
  { code: "CR", name: "Costa Rica" },
  { code: "PA", name: "Panama" },
  { code: "DO", name: "Dominican Republic" },
  { code: "JM", name: "Jamaica" },
  { code: "TT", name: "Trinidad and Tobago" },
  { code: "BB", name: "Barbados" },
  { code: "BS", name: "Bahamas" },
  { code: "BZ", name: "Belize" },
  { code: "GY", name: "Guyana" },
  { code: "SR", name: "Suriname" },
  { code: "RU", name: "Russia" },
  { code: "CN", name: "China" },
  { code: "TR", name: "Turkey" },
  { code: "IL", name: "Israel" },
  { code: "NZ", name: "New Zealand" },
];

// Country names come from the `countries` namespace, keyed by ISO code and
// generated from Intl.DisplayNames. Resolved per render, not at module scope:
// Store.jsx sets I18n.locale after the shop settings load, so anything
// computed at import time would freeze on English.
const countryName = (code, fallback) =>
  I18n.t(`countries.${code}`, { defaultValue: fallback });

const CountrySelector = ({
  selectedCountry,
  onCountryChange,
  placeholder = "Search countries...",
  label = "Select Country/Region",
  labelHidden = false,
  width = "250px",
  /** Use native Select dropdown instead of searchable Popover. More reliable in embedded/iframe (e.g. India plans page). */
  useSelect = false,
}) => {
  const [searchValue, setSearchValue] = useState("");
  const [popoverActive, setPopoverActive] = useState(false);

  const localisedCountries = useMemo(
    () =>
      allCountries.map((c) => ({ ...c, name: countryName(c.code, c.name) })),
    []
  );

  const selectOptions = useMemo(
    () => localisedCountries.map((c) => ({ value: c.code, label: c.name })),
    [localisedCountries]
  );

  // Filter countries for search
  const filteredCountries = useMemo(() => {
    if (!searchValue) return localisedCountries;
    return localisedCountries.filter(
      (country) =>
        country.name.toLowerCase().includes(searchValue.toLowerCase()) ||
        country.code.toLowerCase().includes(searchValue.toLowerCase())
    );
  }, [searchValue, localisedCountries]);

  const selectedCountryName =
    localisedCountries.find((country) => country.code === selectedCountry)
      ?.name || "";

  const handleSelect = useCallback(
    (countryCode) => {
      onCountryChange(countryCode);
      setSearchValue("");
      setPopoverActive(false);
    },
    [onCountryChange]
  );

  // Reliable native-style dropdown: no Popover/portal, works in all contexts
  if (useSelect) {
    return (
      <div style={{ minWidth: width }}>
        <Select
          label={label}
          labelHidden={labelHidden}
          options={selectOptions}
          value={selectedCountry || ""}
          placeholder={placeholder}
          onChange={(value) => onCountryChange(value)}
        />
      </div>
    );
  }

  const handleTextFieldChange = (value) => {
    setSearchValue(value);
    setPopoverActive(true);
  };

  const activator = (
    <TextField
      value={popoverActive ? searchValue : selectedCountryName}
      onChange={handleTextFieldChange}
      onFocus={() => setPopoverActive(true)}
      label={label}
      labelHidden={labelHidden}
      placeholder={placeholder}
      autoComplete="off"
    />
  );

  return (
    <div style={{ minWidth: width }}>
      <Popover
        active={popoverActive}
        activator={activator}
        onClose={() => setPopoverActive(false)}
        autofocusTarget="none"
        preventCloseOnChildOverlayClick
      >
        <Box padding="200">
          <div style={{ maxHeight: "200px", overflowY: "auto" }}>
            {filteredCountries.length > 0 ? (
              <ul style={{ listStyle: "none", margin: 0, padding: 0 }}>
                {filteredCountries.map((country) => (
                  <li key={country.code}>
                    <button
                      type="button"
                      onClick={(e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        handleSelect(country.code);
                      }}
                      style={{
                        display: "block",
                        width: "100%",
                        padding: "12px 16px",
                        textAlign: "left",
                        border: "none",
                        background: "transparent",
                        cursor: "pointer",
                        fontSize: "14px",
                        fontFamily: "inherit",
                      }}
                      onMouseDown={(e) => e.preventDefault()}
                    >
                      <Text as="span" variant="bodyMd">
                        {country.name}
                      </Text>
                    </button>
                  </li>
                ))}
              </ul>
            ) : (
              <Text variant="bodyMd" tone="subdued">
                {I18n.t("country_selector.no_countries_found")}
              </Text>
            )}
          </div>
        </Box>
      </Popover>
    </div>
  );
};

export default CountrySelector;
export { allCountries };
