import React from "react";
import { BlockStack, InlineStack, Box, Text, Checkbox, Select, ChoiceList } from "@shopify/polaris";
import I18n from "../../../../i18n-lang";

const t = (key, defaultValue, opts = {}) =>
  I18n.t(`whatsapp_inbox_settings.${key}`, { defaultValue, ...opts });

export const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

const DAY_LABELS = {
  mon: "Monday",
  tue: "Tuesday",
  wed: "Wednesday",
  thu: "Thursday",
  fri: "Friday",
  sat: "Saturday",
  sun: "Sunday",
};

const pad = (n) => String(n).padStart(2, "0");

const TIME_OPTIONS = (() => {
  const options = [];
  for (let h = 0; h < 24; h++) {
    for (const m of [0, 30]) {
      const value = `${pad(h)}:${pad(m)}`;
      options.push({ label: value, value });
    }
  }
  options.push({ label: "23:59", value: "23:59" });
  return options;
})();

export const defaultHours = () =>
  DAYS.reduce((acc, day) => ({ ...acc, [day]: day === "sun" ? [] : [["09:00", "18:00"]] }), {});

const isAlwaysOpen = (hours) => !hours || Object.keys(hours).length === 0;

const BusinessHoursEditor = ({ hours, timezone, onChange }) => {
  const alwaysOpen = isAlwaysOpen(hours);

  const setMode = ([mode]) => onChange(mode === "always" ? {} : defaultHours());

  const setDay = (day, ranges) => onChange({ ...hours, [day]: ranges });

  return (
    <BlockStack gap="300">
      <ChoiceList
        title={t("hours.mode_title", "When are you open?")}
        titleHidden
        choices={[
          { label: t("hours.always_open", "Open all the time"), value: "always" },
          { label: t("hours.custom", "Set business hours"), value: "custom" },
        ]}
        selected={[alwaysOpen ? "always" : "custom"]}
        onChange={setMode}
      />
      {!alwaysOpen && (
        <BlockStack gap="200">
          {DAYS.map((day) => {
            const ranges = Array.isArray(hours[day]) ? hours[day] : [];
            const closed = ranges.length === 0;
            const [from, to] = ranges[0] || ["09:00", "18:00"];
            const invalid = !closed && to <= from;
            return (
              <Box key={day} paddingBlockEnd="100">
                <InlineStack gap="300" blockAlign="center" wrap>
                  <Box minWidth="96px">
                    <Text as="span" fontWeight="medium">
                      {t(`hours.days.${day}`, DAY_LABELS[day])}
                    </Text>
                  </Box>
                  <Checkbox
                    label={t("away.closed", "Closed")}
                    checked={closed}
                    onChange={(checked) => setDay(day, checked ? [] : [["09:00", "18:00"]])}
                  />
                  {!closed && (
                    <InlineStack gap="200" blockAlign="center" wrap={false}>
                      <Select
                        label={t("hours.opens", "Opens")}
                        labelHidden
                        options={TIME_OPTIONS}
                        value={from}
                        onChange={(value) => setDay(day, [[value, to], ...ranges.slice(1)])}
                      />
                      <Text as="span" tone="subdued">
                        {t("hours.to", "to")}
                      </Text>
                      <Select
                        label={t("hours.closes", "Closes")}
                        labelHidden
                        options={TIME_OPTIONS}
                        value={to}
                        onChange={(value) => setDay(day, [[from, value], ...ranges.slice(1)])}
                        error={invalid ? t("hours.close_after_open", "Must be after opening time") : undefined}
                      />
                    </InlineStack>
                  )}
                </InlineStack>
              </Box>
            );
          })}
        </BlockStack>
      )}
      {timezone && (
        <Text as="p" variant="bodySm" tone="subdued">
          {t("away.timezone", "Times are in your store's time zone: %{zone}", { zone: timezone })}
        </Text>
      )}
    </BlockStack>
  );
};

export const hoursAreValid = (hours) =>
  isAlwaysOpen(hours) ||
  DAYS.every((day) => (hours[day] || []).every(([from, to]) => typeof from === "string" && to > from));

export default BusinessHoursEditor;
