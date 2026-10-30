import React from "react";
import { TextField } from "@shopify/polaris";
import styled from "styled-components";
import { isHexColor } from "../utils";
import { t } from "../i18n";

const Swatch = styled.label`
  display: inline-flex;
  width: 24px;
  height: 24px;
  border-radius: 6px;
  border: 1px solid var(--p-color-border, #c9cccf);
  overflow: hidden;
  cursor: pointer;
  background: ${(props) => props.$color};

  input {
    opacity: 0;
    width: 100%;
    height: 100%;
    border: 0;
    padding: 0;
    cursor: pointer;
  }
`;

/** Hex colour input with a native colour picker as its prefix. */
const ColorField = ({ label, value, onChange, helpText, disabled }) => {
  const valid = isHexColor(value);
  const pickerValue = valid
    ? value.length === 4
      ? `#${value[1]}${value[1]}${value[2]}${value[2]}${value[3]}${value[3]}`
      : value
    : "#000000";
  return (
    <TextField
      label={label}
      value={value || ""}
      onChange={onChange}
      autoComplete="off"
      disabled={disabled}
      helpText={helpText}
      placeholder="#111111"
      error={value && !valid ? t("common.invalid_color", "Enter a hex colour, for example #111111") : undefined}
      prefix={
        <Swatch $color={valid ? value : "#ffffff"} aria-label={label}>
          <input
            type="color"
            value={pickerValue}
            disabled={disabled}
            onChange={(event) => onChange(event.target.value)}
          />
        </Swatch>
      }
    />
  );
};

export default ColorField;
