import React from "react";
import { BlockStack, Button, ButtonGroup, Card, Checkbox, InlineGrid, InlineStack, Select, TextField } from "@shopify/polaris";
import ResourceTargetPicker from "../components/ResourceTargetPicker";
import { COUNTRIES } from "../constants";
import { todayIso } from "../utils";
import { t } from "../i18n";

export const defaultFilters = () => ({
  from: todayIso(-29),
  to: todayIso(0),
  country: "",
  device: "",
  product_id: "",
  compare: false,
});

const PRESETS = [7, 30, 90];

/** Date range, country, product, device (ANL-2) and compare-to-previous (ANL-4). */
const Filters = ({ filters, onChange, canCompare }) => {
  const set = (patch) => onChange({ ...filters, ...patch });
  const activePreset = PRESETS.find((days) => filters.to === todayIso(0) && filters.from === todayIso(-(days - 1)));
  const invalid = filters.from && filters.to && filters.from > filters.to;

  return (
    <Card>
      <BlockStack gap="400">
        <InlineStack gap="300" blockAlign="end" wrap>
          <ButtonGroup variant="segmented">
            {PRESETS.map((days) => (
              <Button key={days} pressed={activePreset === days} onClick={() => set({ from: todayIso(-(days - 1)), to: todayIso(0) })}>
                {t("analytics.last_days", "Last %{days} days", { days })}
              </Button>
            ))}
          </ButtonGroup>
          <div style={{ flex: "1 1 140px" }}>
            <TextField
              label={t("analytics.from", "From")}
              type="date"
              value={filters.from}
              max={filters.to || undefined}
              onChange={(value) => set({ from: value })}
              autoComplete="off"
            />
          </div>
          <div style={{ flex: "1 1 140px" }}>
            <TextField
              label={t("analytics.to", "To")}
              type="date"
              value={filters.to}
              max={todayIso(0)}
              onChange={(value) => set({ to: value })}
              error={invalid ? t("analytics.range_invalid", "The end date is before the start date.") : undefined}
              autoComplete="off"
            />
          </div>
        </InlineStack>
        <InlineGrid columns={{ xs: 1, sm: 3 }} gap="400">
          <Select
            label={t("analytics.filter_country", "Country")}
            options={[
              { value: "", label: t("analytics.all_countries", "All countries") },
              ...COUNTRIES.map((country) => ({ value: country.value, label: country.label })),
            ]}
            value={filters.country}
            onChange={(value) => set({ country: value })}
          />
          <Select
            label={t("analytics.filter_device", "Device")}
            options={[
              { value: "", label: t("analytics.all_devices", "All devices") },
              { value: "mobile", label: t("common.mobile", "Mobile") },
              { value: "tablet", label: t("analytics.device_tablet", "Tablet") },
              { value: "desktop", label: t("common.desktop", "Desktop") },
            ]}
            value={filters.device}
            onChange={(value) => set({ device: value })}
          />
          <ResourceTargetPicker
            type="product"
            multiple={false}
            label={t("analytics.filter_product", "Product")}
            buttonLabel={filters.product_id ? t("analytics.change_product", "Change product") : t("analytics.all_products", "All products")}
            ids={filters.product_id ? [filters.product_id] : []}
            onChange={(ids) => set({ product_id: ids[0] || "" })}
          />
        </InlineGrid>
        {canCompare && (
          <Checkbox
            label={t("analytics.compare", "Compare with the previous period")}
            checked={!!filters.compare}
            onChange={(value) => set({ compare: value })}
          />
        )}
      </BlockStack>
    </Card>
  );
};

export default Filters;
