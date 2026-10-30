import React from "react";
import {
  Card,
  FormLayout,
  Text,
  TextField,
  BlockStack,
  Icon,
  Tag,
  Select,
  Checkbox,
  Tooltip,
} from "@shopify/polaris";
import { LocationMajor } from "@shopify/polaris-icons";
import I18n from "../../i18n-lang";
import countries from "../Country"; // assumes you have a country list

const HelpIcon = ({ content }) => (
  <Tooltip content={content}>
    <span
      style={{ display: "inline-flex", alignItems: "center", marginLeft: 4 }}
    >
      {/* <Icon source={QuestionMarkCircleIcon} tone="subdued" /> */}
    </span>
  </Tooltip>
);

export default function LocationRulesCard({
  setting,
  handleSettingChange,
  provinceData = { provinces: [] }, // Fallback for province API data
}) {
  const selectedCountries = setting.selectedCountries?.split(",") || [];

  const handleCountriesChange = (value) => {
    handleSettingChange("selectedCountries")(value);
  };

  const showProvinces = setting.showProvinces?.split(",") || [];
  const hideProvinces = setting.hideProvinces?.split(",") || [];
  const selectedZips = setting.selectedZips || "";
  const excludedZips = setting.excludedZips || "";

  return (
    /* Countries, provinces and postcodes each get a card: as one they put
       seven controls on screen, and Built for Shopify allows five. */
    <BlockStack gap="400">
    <Card>
      <BlockStack alignment="center" spacing="tight">
        <Icon source={LocationMajor} tone="base" />
        <Text as="h2" variant="headingSm">
          {I18n.t("cod_show_hide.location_rules_heading")}
        </Text>
      </BlockStack>

      <FormLayout>
        {/* Country Selection */}
        <BlockStack alignment="center">
          <span>{I18n.t("cod_show_hide.select_countries_label")}</span>
          <HelpIcon
            content={I18n.t("cod_show_hide.select_countries_help_text")}
          />
        </BlockStack>

        <Select
          label=""
          options={countries}
          value={selectedCountries}
          onChange={handleCountriesChange}
          multiple
        />

        {selectedCountries.length > 0 && (
          <BlockStack wrap spacing="tight">
            {selectedCountries.map((code) => {
              const label =
                countries.find((c) => c.value === code)?.label || code;
              return <Tag key={code}>{label}</Tag>;
            })}
          </BlockStack>
        )}

      </FormLayout>
    </Card>

    <Card>
      <BlockStack alignment="center" spacing="tight">
        <Text as="h2" variant="headingSm">
          {I18n.t("cod_show_hide.province_rules_heading", {
            defaultValue: "State and province rules",
          })}
        </Text>
      </BlockStack>

      <FormLayout>
        {/* Province Rules */}
        <Checkbox
          label={
            <BlockStack alignment="center">
              <span>
                {I18n.t("cod_show_hide.hide_show_based_on_provinces_label")}
              </span>
              <HelpIcon
                content={I18n.t(
                  "cod_show_hide.hide_show_based_on_provinces_tooltip"
                )}
              />
            </BlockStack>
          }
          checked={!!(showProvinces.length || hideProvinces.length)}
          onChange={(checked) => {
            if (!checked) {
              handleSettingChange("showProvinces")("");
              handleSettingChange("hideProvinces")("");
            }
          }}
        />

        {(showProvinces.length || hideProvinces.length) > 0 && (
          <BlockStack distribution="fillEvenly" wrap>
            <Select
              label={I18n.t("cod_show_hide.select_provinces_to_show_label")}
              options={provinceData.provinces.map((p) => ({
                label: `${p.countryName} - ${p.provinceName}`,
                value: p.provinceCode,
              }))}
              value={showProvinces}
              onChange={handleSettingChange("showProvinces")}
              multiple
            />
            <Select
              label={I18n.t("cod_show_hide.select_provinces_to_hide_label")}
              options={provinceData.provinces.map((p) => ({
                label: `${p.countryName} - ${p.provinceName}`,
                value: p.provinceCode,
              }))}
              value={hideProvinces}
              onChange={handleSettingChange("hideProvinces")}
              multiple
            />
          </BlockStack>
        )}

      </FormLayout>
    </Card>

    <Card>
      <BlockStack alignment="center" spacing="tight">
        <Text as="h2" variant="headingSm">
          {I18n.t("cod_show_hide.zip_rules_heading", {
            defaultValue: "Postcode rules",
          })}
        </Text>
      </BlockStack>

      <FormLayout>
        {/* ZIP Code Rules */}
        <Checkbox
          label={
            <BlockStack alignment="center">
              <span>
                {I18n.t("cod_show_hide.hide_show_based_on_zip_label")}
              </span>
              <HelpIcon
                content={I18n.t("cod_show_hide.hide_show_based_on_zip_tooltip")}
              />
            </BlockStack>
          }
          checked={!!(selectedZips || excludedZips)}
          onChange={(checked) => {
            if (!checked) {
              handleSettingChange("selectedZips")("");
              handleSettingChange("excludedZips")("");
            }
          }}
        />

        {(selectedZips || excludedZips) && (
          <BlockStack vertical spacing="tight">
            <TextField
              label={I18n.t("cod_show_hide.zip_codes_to_enable_label")}
              value={selectedZips}
              onChange={handleSettingChange("selectedZips")}
              placeholder="560001, 560002"
              helpText={I18n.t("cod_show_hide.zip_codes_help_text")}
            />
            <TextField
              label={I18n.t("cod_show_hide.zip_codes_to_hide_label")}
              value={excludedZips}
              onChange={handleSettingChange("excludedZips")}
              placeholder="560003, 560004"
              helpText={I18n.t("cod_show_hide.zip_codes_help_text")}
            />
          </BlockStack>
        )}
      </FormLayout>
    </Card>
    </BlockStack>
  );
}
