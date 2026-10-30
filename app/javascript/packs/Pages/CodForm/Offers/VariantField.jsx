import React from "react";
import ResourceTargetPicker from "../components/ResourceTargetPicker";
import { t } from "../i18n";

/** Single product-variant picker storing the numeric id as a string (or null). */
const VariantField = ({ label, value, onChange, helpText }) => (
  <ResourceTargetPicker
    type="variant"
    multiple={false}
    label={label}
    buttonLabel={value ? t("offers.change_variant", "Change product") : t("offers.select_variant", "Select product")}
    ids={value ? [String(value)] : []}
    onChange={(ids) => onChange(ids[0] ? String(ids[0]) : null)}
    helpText={helpText}
  />
);

export default VariantField;
