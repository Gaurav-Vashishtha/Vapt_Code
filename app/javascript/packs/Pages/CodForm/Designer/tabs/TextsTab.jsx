import React, { useMemo, useRef, useState } from "react";
import { Banner, BlockStack, Button, Card, InlineGrid, InlineStack, Select, Text, TextField } from "@shopify/polaris";
import { LIMITS, SHIPPED_LOCALES, localeName } from "../../constants";
import { t } from "../../i18n";
import { addTextLocale, allTextKeys, defaultText, setTextOverride, textGroupOf, TEXT_GROUPS } from "../texts";
import { humanizeKey, textGroupName } from "../fieldLabels";

const PAGE = 40;

/** Every buyer-facing string, per locale (FRM-10, FRM-19). Only overrides are stored. */
const TextsTab = ({ config, setConfig, defaultsTexts, locale, locales, onLocaleChange }) => {
  const [group, setGroup] = useState("general");
  const [query, setQuery] = useState("");
  const [shown, setShown] = useState(PAGE);
  const [adding, setAdding] = useState("");
  // One line or several is decided once per text: switching while the merchant types would
  // swap the input for a textarea and drop the cursor.
  const multilineOf = useRef({});
  const isMultiline = (key) => {
    const id = `${locale}:${key}`;
    if (multilineOf.current[id] === undefined) {
      multilineOf.current[id] = (own[key] || defaultText(defaultsTexts, locale, key)).length > 70;
    }
    return multilineOf.current[id];
  };
  const texts = config.texts || {};
  const own = texts[locale] || {};
  const usedLocales = Object.keys(texts);
  const canAddLocale = usedLocales.length < LIMITS.TEXT_LOCALES_MAX;

  const keys = useMemo(() => allTextKeys(config, defaultsTexts), [config, defaultsTexts]);
  const needle = query.trim().toLowerCase();
  const filtered = keys.filter((key) => {
    if (needle) {
      const value = `${key} ${own[key] || ""} ${defaultText(defaultsTexts, locale, key)}`.toLowerCase();
      return value.includes(needle);
    }
    return textGroupOf(key) === group;
  });

  const candidates = Array.from(new Set([...SHIPPED_LOCALES, ...Object.keys(defaultsTexts || {})])).filter(
    (code) => !locales.includes(code),
  );
  const hasShippedDefaults = !!(defaultsTexts && defaultsTexts[String(locale).split("-")[0]]);

  const resetLocale = () =>
    setConfig((current) => {
      const next = { ...(current.texts || {}) };
      delete next[locale];
      return { ...current, texts: next };
    });

  return (
    <BlockStack gap="400">
      <Card>
        <BlockStack gap="400">
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            <Select
              label={t("designer.texts_locale", "Language")}
              options={locales.map((code) => ({
                value: code,
                label: `${localeName(code)}${texts[code] ? ` (${Object.keys(texts[code]).length})` : ""}`,
              }))}
              value={locale}
              onChange={(value) => {
                setShown(PAGE);
                onLocaleChange(value);
              }}
            />
            <Select
              label={t("designer.texts_add_locale", "Add a language")}
              options={[
                { value: "", label: t("common.select", "Select") },
                ...candidates.map((code) => ({ value: code, label: localeName(code) })),
              ]}
              value={adding}
              disabled={!canAddLocale || candidates.length === 0}
              helpText={!canAddLocale ? t("designer.texts_locale_limit", "You can edit texts in up to 12 languages.") : undefined}
              onChange={(value) => {
                setAdding("");
                if (!value) return;
                // Stored in the draft right away: the language stays in the "Language" list when
                // the merchant switches to another one, and the save bar offers to save it.
                setConfig((current) => addTextLocale(current, value));
                setShown(PAGE);
                onLocaleChange(value);
              }}
            />
          </InlineGrid>
          <Select
            label={t("designer.form_language", "Show the form in")}
            helpText={
              config.language
                ? t("designer.form_language_fixed_help", "Every buyer sees the form in this language, whatever language your storefront is in.")
                : t("designer.form_language_setup_help", "This form uses the language chosen in Setup → Form language. Pick a language here only to show this form in another one.")
            }
            options={[
              { value: "", label: t("designer.form_language_setup", "Same as Setup (default)") },
              ...Array.from(new Set([...SHIPPED_LOCALES, ...locales])).map((code) => ({ value: code, label: localeName(code) })),
            ]}
            value={config.language || ""}
            onChange={(value) => {
              setConfig((current) => ({ ...(value ? addTextLocale(current, value) : current), language: value }));
              if (value) {
                setShown(PAGE);
                onLocaleChange(value);
              }
            }}
          />
          {!hasShippedDefaults && (
            <Banner tone="info">
              <p>{t("designer.texts_no_defaults", "COD King has no built-in texts for this language yet, so buyers see English wherever you leave a text empty.")}</p>
            </Banner>
          )}
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            <Select
              label={t("designer.texts_group", "Section")}
              options={TEXT_GROUPS.map((item) => ({ value: item.id, label: textGroupName(item.id) }))}
              value={group}
              disabled={!!needle}
              onChange={(value) => {
                setGroup(value);
                setShown(PAGE);
              }}
            />
            <TextField
              label={t("designer.texts_search", "Search all texts")}
              value={query}
              onChange={(value) => {
                setQuery(value);
                setShown(PAGE);
              }}
              clearButton
              onClearButtonClick={() => setQuery("")}
              autoComplete="off"
            />
          </InlineGrid>
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="400">
          <InlineStack align="space-between" blockAlign="center">
            <Text as="h3" variant="headingSm">
              {needle ? t("designer.texts_results", "%{count} texts", { count: filtered.length }) : textGroupName(group)}
            </Text>
            <Button onClick={resetLocale} disabled={!texts[locale]} tone="critical" variant="plain">
              {t("designer.texts_reset", "Reset this language to defaults")}
            </Button>
          </InlineStack>
          {filtered.length === 0 && (
            <Text as="p" tone="subdued">
              {t("designer.texts_empty", "No text matches your search.")}
            </Text>
          )}
          {filtered.slice(0, shown).map((key) => (
            <TextField
              key={key}
              label={humanizeKey(key)}
              value={own[key] || ""}
              placeholder={defaultText(defaultsTexts, locale, key)}
              onChange={(value) => setConfig((current) => setTextOverride(current, locale, key, value))}
              maxLength={LIMITS.TEXT_MAX_CHARS}
              multiline={isMultiline(key) ? 2 : false}
              autoComplete="off"
            />
          ))}
          {filtered.length > shown && (
            <InlineStack align="center">
              <Button onClick={() => setShown((value) => value + PAGE)}>{t("common.show_more", "Show more")}</Button>
            </InlineStack>
          )}
          <Text as="p" variant="bodySm" tone="subdued">
            {t("designer.variables_help", "Keep variables such as {total}, {first_name} and {order_name} exactly as written; they are replaced with real values.")}
          </Text>
        </BlockStack>
      </Card>
    </BlockStack>
  );
};

export default TextsTab;
