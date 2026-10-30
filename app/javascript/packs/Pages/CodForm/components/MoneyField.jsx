import React, { useEffect, useState } from "react";
import { TextField } from "@shopify/polaris";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { centsToInput, inputToCents } from "../money";

/**
 * Decimal input bound to an integer `_cents` value (amount × 100).
 * An empty input is `null` ("no limit") unless `required`, where it is 0.
 */
const MoneyField = ({ label, value, onChange, currency, helpText, error, disabled, required, placeholder, labelHidden }) => {
  const bootstrap = useCodFormBootstrap();
  const [text, setText] = useState(centsToInput(value));

  // Follow outside changes (discard, reload) without fighting the typist.
  useEffect(() => {
    if (inputToCents(text) !== (value === undefined ? null : value)) setText(centsToInput(value));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);

  const handleChange = (next) => {
    setText(next);
    const cents = inputToCents(next);
    onChange(cents === null && required ? 0 : cents);
  };

  return (
    <TextField
      label={label}
      labelHidden={labelHidden}
      type="number"
      min={0}
      step={0.01}
      inputMode="decimal"
      value={text}
      onChange={handleChange}
      autoComplete="off"
      prefix={currency || (bootstrap && bootstrap.currency) || undefined}
      helpText={helpText}
      error={error}
      disabled={disabled}
      placeholder={placeholder}
    />
  );
};

export default MoneyField;
