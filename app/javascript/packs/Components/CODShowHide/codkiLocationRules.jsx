import React from "react";
import { Card, BlockStack, Checkbox, InlineStack, Tag } from "@shopify/polaris";
import MultiSelect from "./codkiMultiSelect";
import I18n from "../../i18n-lang";
import countries from "../Country";

function LocationRules({
  setting,
  handleSettingChange,
  renderTextField,
  renderMultiSelect,
  provincesChecked,
  zipCodesChecked,
  checkedChangeHandler,
  setProvincesChecked,
  setZipCodesChecked,
  disabled,
  provinceData,
}) {
  const zipCodesEnableField = renderTextField(
    I18n.t("cod_show_hide.zip_codes_to_enable_label"),
    setting.selectedZips,
    handleSettingChange("selectedZips"),
    I18n.t("cod_show_hide.zip_codes_help_text"),
    I18n.t("cod_show_hide.zip_codes_placeholder"),
    "560001,560002,560010",
    3,
    false,
    "400px",
    setting.excludedZips && setting.excludedZips.length > 0
  );

  const zipCodesExcludeField = renderTextField(
    I18n.t("cod_show_hide.zip_codes_to_hide_label"),
    setting.excludedZips,
    handleSettingChange("excludedZips"),
    I18n.t("cod_show_hide.zip_codes_help_text"),
    I18n.t("cod_show_hide.zip_codes_placeholder"),
    "560001,560002,560010",
    3,
    false,
    "400px",
    setting.selectedZips && setting.selectedZips.length > 0
  );

  return (
    <Card roundedAbove="sm" padding="400">
      <div
        style={{
          opacity: disabled ? 0.5 : 1,
          pointerEvents: disabled ? "none" : "auto",
        }}
      >
        <BlockStack gap="400">
          {renderMultiSelect(
            "selectedCountries",
            I18n.t("cod_show_hide.select_countries_label"),
            countries,
            I18n.t("cod_show_hide.select_countries_help_text")
          )}

          {setting.selectedCountries && (
            <Tag>
              {I18n.t("cod_show_hide.selected_label")}:{" "}
              {setting.selectedCountries}
            </Tag>
          )}

          <InlineStack align="start" gap="100" blockAlign="center" wrap>
            <Checkbox
              label={I18n.t("cod_show_hide.hide_show_based_on_provinces_label")}
              checked={provincesChecked}
              onChange={
                disabled
                  ? () => {}
                  : (checked) =>
                      checkedChangeHandler(
                        checked,
                        setProvincesChecked,
                        "provincesChecked"
                      )
              }
              disabled={disabled}
            />
          </InlineStack>

          <BlockStack
            style={{ display: provincesChecked ? "block" : "none" }}
            gap="400"
          >
            {renderMultiSelect(
              "showProvinces",
              I18n.t("cod_show_hide.select_provinces_to_show_label"),
              provinceData?.provinces?.map((province) => ({
                value: province.provinceCode,
                label: `${province.countryName} - ${province.provinceName}`,
              })) || [],
              I18n.t("cod_show_hide.select_provinces_to_show_help_text"),
              false,
              "500px",
              setting.hideProvinces && setting.hideProvinces.length > 0
            )}

            {setting.showProvinces && (
              <Tag>
                {I18n.t("cod_show_hide.selected_label")}:{" "}
                {setting.showProvinces}
              </Tag>
            )}

            {renderMultiSelect(
              "hideProvinces",
              I18n.t("cod_show_hide.select_provinces_to_hide_label"),
              provinceData?.provinces?.map((province) => ({
                value: province.provinceCode,
                label: `${province.countryName} - ${province.provinceName}`,
              })) || [],
              I18n.t("cod_show_hide.select_provinces_to_hide_help_text"),
              false,
              "500px",
              setting.showProvinces && setting.showProvinces.length > 0
            )}

            {setting.hideProvinces && (
              <Tag>
                {I18n.t("cod_show_hide.selected_label")}:{" "}
                {setting.hideProvinces}
              </Tag>
            )}
          </BlockStack>

          <InlineStack align="start" gap="100" blockAlign="center" wrap>
            <Checkbox
              label={I18n.t("cod_show_hide.hide_show_based_on_zip_label")}
              checked={zipCodesChecked}
              onChange={
                disabled
                  ? () => {}
                  : (checked) =>
                      checkedChangeHandler(
                        checked,
                        setZipCodesChecked,
                        "zipCodesChecked"
                      )
              }
              disabled={disabled}
            />
          </InlineStack>
          {zipCodesChecked && (
            <BlockStack gap="400">
              {zipCodesEnableField}
              {zipCodesExcludeField}
            </BlockStack>
          )}
        </BlockStack>
      </div>
    </Card>
  );
}

export default LocationRules;
