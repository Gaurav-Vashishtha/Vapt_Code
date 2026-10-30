import React, { useState } from "react";
import { TextField, Select } from "@shopify/polaris";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { localeName } from "../constants";
import { t } from "../i18n";

/**
 * Edits a `{default: "...", hu: "..."}` map (button labels, offer titles…).
 * `default` is mandatory and is what a locale without its own text shows.
 * With `fixedKeys` the selector lists those keys instead (e.g. plain locales
 * for thank-you messages, where there is no `default` key).
 */
const LocalizedTextField = ({
  label,
  value,
  onChange,
  helpText,
  multiline,
  maxLength,
  placeholder,
  disabled,
  fixedKeys,
  error,
}) => {
  const bootstrap = useCodFormBootstrap();
  const map = value && typeof value === "object" ? value : {};
  const shopLocales = (bootstrap && bootstrap.locales) || ["en"];
  const keys = fixedKeys && fixedKeys.length
    ? fixedKeys
    : ["default", ...shopLocales.filter((locale) => locale !== "default")];
  const allKeys = [...keys, ...Object.keys(map).filter((key) => !keys.includes(key))];
  const [locale, setLocale] = useState(allKeys[0]);
  const current = allKeys.includes(locale) ? locale : allKeys[0];

  const handleChange = (text) => {
    const next = { ...map };
    if (text === "" && current !== "default") delete next[current];
    else next[current] = text;
    onChange(next);
  };

  const options = allKeys.map((key) => ({
    value: key,
    label:
      key === "default"
        ? t("common.locale_default", "Default")
        : `${localeName(key)}${map[key] ? " •" : ""}`,
  }));

  return (
    <TextField
      label={label}
      value={map[current] || ""}
      onChange={handleChange}
      autoComplete="off"
      multiline={multiline}
      maxLength={maxLength}
      showCharacterCount={!!maxLength}
      disabled={disabled}
      error={error}
      placeholder={current === "default" ? placeholder : map.default || placeholder}
      helpText={helpText}
      connectedRight={
        allKeys.length > 1 ? (
          <Select
            label={t("common.language", "Language")}
            labelHidden
            options={options}
            value={current}
            onChange={setLocale}
            disabled={disabled}
          />
        ) : undefined
      }
    />
  );
};

export default LocalizedTextField;
