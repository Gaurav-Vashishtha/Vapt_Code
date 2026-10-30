import React, { useCallback, useEffect, useRef, useState } from "react";
import { Badge, Banner, BlockStack, Button, Card, Checkbox, InlineGrid, InlineStack, Select, Text, TextField } from "@shopify/polaris";
import { codFormApi, parseError } from "../api";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { DEFAULT_SHEET_COLUMNS, FEATURES, SHEET_COLUMNS } from "../constants";
import { deepEqual, formatDateTime, moveItem } from "../utils";
import { t } from "../i18n";
import Gate from "../components/Gate";
import Screen, { SaveErrorBanner } from "../components/Screen";
import ScreenSaveBar from "../components/ScreenSaveBar";
import ModuleDisabled from "../components/ModuleDisabled";
import SortableList from "../Designer/SortableList";

const columnLabel = (key) => {
  switch (key) {
    case "order_name":
      return t("sheets.col_order_name", "Order number");
    case "order_id":
      return t("sheets.col_order_id", "Order ID");
    case "created_at":
      return t("sheets.col_created_at", "Date");
    case "first_name":
      return t("sheets.col_first_name", "First name");
    case "last_name":
      return t("sheets.col_last_name", "Last name");
    case "phone":
      return t("sheets.col_phone", "Phone");
    case "email":
      return t("sheets.col_email", "Email");
    case "address1":
      return t("sheets.col_address1", "Address");
    case "address2":
      return t("sheets.col_address2", "Address line 2");
    case "city":
      return t("sheets.col_city", "City");
    case "province":
      return t("sheets.col_province", "State / province");
    case "zip":
      return t("sheets.col_zip", "Postal code");
    case "country":
      return t("sheets.col_country", "Country");
    case "items":
      return t("sheets.col_items", "Items");
    case "quantity":
      return t("sheets.col_quantity", "Quantity");
    case "subtotal":
      return t("sheets.col_subtotal", "Subtotal");
    case "discount":
      return t("sheets.col_discount", "Discount");
    case "shipping":
      return t("sheets.col_shipping", "Shipping");
    case "cod_fee":
      return t("sheets.col_cod_fee", "COD fee");
    case "total":
      return t("sheets.col_total", "Total");
    case "currency":
      return t("sheets.col_currency", "Currency");
    case "shipping_rate":
      return t("sheets.col_shipping_rate", "Shipping rate");
    case "discount_code":
      return t("sheets.col_discount_code", "Discount code");
    case "utm_source":
      return t("sheets.col_utm_source", "UTM source");
    case "utm_medium":
      return t("sheets.col_utm_medium", "UTM medium");
    case "utm_campaign":
      return t("sheets.col_utm_campaign", "UTM campaign");
    case "note":
      return t("sheets.col_note", "Order note");
    default:
      return key.startsWith("custom:") ? t("sheets.col_custom", "Custom field %{key}", { key: key.slice(7) }) : key;
  }
};

const shapeConfig = (config) => ({
  spreadsheet_id: (config && config.spreadsheet_id) || "",
  sheet_name: (config && config.sheet_name) || "Sheet1",
  columns: config && Array.isArray(config.columns) && config.columns.length ? config.columns : DEFAULT_SHEET_COLUMNS,
});

/** /integrations/google-sheets — connect a Google account, pick a sheet, map columns (INT-1). */
const GoogleSheetsPage = () => {
  const bootstrap = useCodFormBootstrap();
  const [item, setItem] = useState(undefined);
  const [config, setConfig] = useState(shapeConfig(null));
  const [savedConfig, setSavedConfig] = useState(shapeConfig(null));
  const [sheets, setSheets] = useState(null);
  const [error, setError] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [busy, setBusy] = useState(null);
  const [unavailable, setUnavailable] = useState(false);
  const [waiting, setWaiting] = useState(false);
  const [customKey, setCustomKey] = useState("");
  const pollRef = useRef(null);

  const load = useCallback(() => {
    setError(null);
    return codFormApi.integrations
      .index()
      .then((response) => {
        const found = ((response && response.items) || []).find((entry) => entry.provider === "google_sheets") || null;
        setItem(found);
        // `available: false` = the feature is not configured on the server (I.5).
        if (found && found.available === false) setUnavailable(true);
        const shaped = shapeConfig(found && found.config);
        setConfig(shaped);
        setSavedConfig(shaped);
        return found;
      })
      .catch((err) => {
        setError(parseError(err));
        return null;
      });
  }, []);

  const connected = !!item && (item.status === "connected" || item.status === "error");

  useEffect(() => {
    if (bootstrap && bootstrap.moduleEnabled) load();
  }, [bootstrap, load]);

  useEffect(() => {
    if (!connected) return;
    codFormApi.integrations
      .googleSheets()
      .then((response) => setSheets((response && response.spreadsheets) || []))
      .catch(() => setSheets([]));
  }, [connected]);

  useEffect(() => () => clearInterval(pollRef.current), []);

  // The OAuth callback page posts the outcome to its opener and closes itself.
  useEffect(() => {
    const onMessage = (event) => {
      if (!event.data || event.data.type !== "codkf:google_sheets") return;
      clearInterval(pollRef.current);
      setWaiting(false);
      if (event.data.ok === false) setActionError({ messages: [], isValidation: false, isGate: false });
      load();
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [load]);

  if (bootstrap && !bootstrap.moduleEnabled) return <ModuleDisabled />;

  const connect = () => {
    setBusy("connect");
    setActionError(null);
    codFormApi.integrations
      .googleAuthUrl()
      .then((response) => {
        if (!response || !response.url) {
          setUnavailable(true);
          return;
        }
        // Google's consent screen opens in its own window; the app stays in the admin.
        const popup = window.open(response.url, "codkf_google_oauth", "width=520,height=680");
        setWaiting(true);
        let ticks = 0;
        clearInterval(pollRef.current);
        pollRef.current = setInterval(() => {
          ticks += 1;
          load().then((found) => {
            const done = found && found.status === "connected";
            if (done || ticks > 90 || (popup && popup.closed && ticks > 2)) {
              clearInterval(pollRef.current);
              setWaiting(false);
            }
          });
        }, 2000);
      })
      .catch((err) => {
        const parsed = parseError(err);
        if (parsed.isNotFound || parsed.status === 503 || parsed.code === "not_available") setUnavailable(true);
        else setActionError(parsed);
      })
      .then(() => setBusy(null));
  };

  const save = () => {
    setBusy("save");
    setActionError(null);
    codFormApi.integrations
      .update("google_sheets", { config })
      .then((saved) => {
        if (saved && saved.provider) setItem(saved);
        setSavedConfig(config);
        if (window.shopify && window.shopify.toast) window.shopify.toast.show(t("integrations.saved", "Saved"));
      })
      .catch((err) => setActionError(parseError(err)))
      .then(() => setBusy(null));
  };

  const disconnect = () => {
    setBusy("disconnect");
    codFormApi.integrations
      .destroy("google_sheets")
      .then(() => {
        setSheets(null);
        return load();
      })
      .catch((err) => setActionError(parseError(err)))
      .then(() => setBusy(null));
  };

  const columns = config.columns;
  const available = [...SHEET_COLUMNS, ...columns.filter((key) => key.startsWith("custom:"))].filter((key) => !columns.includes(key));
  const isDirty = connected && !deepEqual(config, savedConfig);
  const addCustom = () => {
    const key = customKey.trim();
    if (!key) return;
    const column = `custom:${key}`;
    if (!columns.includes(column)) setConfig((current) => ({ ...current, columns: [...current.columns, column] }));
    setCustomKey("");
  };

  return (
    <Screen
      title={t("sheets.title", "Google Sheets")}
      subtitle={t("sheets.subtitle", "Add every COD Form order to a Google Sheet as it is placed.")}
      backPath="/integrations"
      backLabel={t("pixels.back", "Integrations")}
      loading={!bootstrap || (item === undefined && !error)}
      error={error}
      onRetry={load}
    >
      <Gate feature={FEATURES.GOOGLE_SHEETS} title={t("sheets.title", "Google Sheets")}>
        <ScreenSaveBar open={isDirty} saving={busy === "save"} onSave={save} onDiscard={() => setConfig(savedConfig)} />
        <SaveErrorBanner error={actionError} onDismiss={() => setActionError(null)} />
        {unavailable && (
          <Banner tone="warning">
            <p>{t("sheets.unavailable", "Google Sheets is not available right now. Contact support if you need it.")}</p>
          </Banner>
        )}
        {item && item.status === "error" && (
          <Banner tone="critical" title={t("sheets.error_title", "Orders are not reaching your sheet")}>
            <p>{item.last_error || t("sheets.error_body", "Reconnect your Google account and check that the sheet still exists.")}</p>
          </Banner>
        )}

        <Card>
          <BlockStack gap="300">
            <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
              <InlineStack gap="200" blockAlign="center">
                <Text as="h2" variant="headingMd">
                  {t("sheets.account_title", "Google account")}
                </Text>
                {connected ? (
                  <Badge tone="success">{t("integrations.connected_badge", "Connected")}</Badge>
                ) : (
                  <Badge>{t("sheets.not_connected", "Not connected")}</Badge>
                )}
              </InlineStack>
              {connected ? (
                <InlineStack gap="200">
                  <Button onClick={connect} loading={busy === "connect"}>
                    {t("sheets.reconnect", "Reconnect")}
                  </Button>
                  <Button tone="critical" onClick={disconnect} loading={busy === "disconnect"}>
                    {t("integrations.disconnect", "Disconnect")}
                  </Button>
                </InlineStack>
              ) : (
                <Button variant="primary" onClick={connect} loading={busy === "connect" || waiting} disabled={unavailable}>
                  {t("sheets.connect", "Connect Google account")}
                </Button>
              )}
            </InlineStack>
            <Text as="p" tone="subdued">
              {waiting
                ? t("sheets.waiting", "Finish signing in to Google in the window that opened. This page updates by itself.")
                : t("sheets.account_help", "COD King asks only for access to spreadsheets you choose. Google opens in a separate window.")}
            </Text>
            {item && item.last_success_at && (
              <Text as="p" variant="bodySm" tone="subdued">
                {t("sheets.last_success", "Last order added %{date}", { date: formatDateTime(item.last_success_at) })}
              </Text>
            )}
          </BlockStack>
        </Card>

        {connected && (
          <>
            <Card>
              <BlockStack gap="400">
                <Text as="h2" variant="headingMd">
                  {t("sheets.sheet_title", "Spreadsheet")}
                </Text>
                <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                  <Select
                    label={t("sheets.spreadsheet", "Spreadsheet")}
                    options={[
                      { value: "", label: sheets === null ? t("common.loading", "Loading…") : t("common.select", "Select") },
                      ...(sheets || []).map((sheet) => ({ value: sheet.id, label: sheet.name })),
                      ...(config.spreadsheet_id && !(sheets || []).some((sheet) => sheet.id === config.spreadsheet_id)
                        ? [{ value: config.spreadsheet_id, label: config.spreadsheet_id }]
                        : []),
                    ]}
                    value={config.spreadsheet_id}
                    onChange={(value) => setConfig((current) => ({ ...current, spreadsheet_id: value }))}
                    error={!config.spreadsheet_id ? t("sheets.spreadsheet_required", "Choose the spreadsheet to write to.") : undefined}
                  />
                  <TextField
                    label={t("sheets.sheet_name", "Tab name")}
                    value={config.sheet_name}
                    onChange={(value) => setConfig((current) => ({ ...current, sheet_name: value }))}
                    helpText={t("sheets.sheet_name_help", "The tab inside the spreadsheet, for example Sheet1.")}
                    autoComplete="off"
                  />
                </InlineGrid>
              </BlockStack>
            </Card>

            <Card>
              <BlockStack gap="400">
                <BlockStack gap="100">
                  <Text as="h2" variant="headingMd">
                    {t("sheets.columns_title", "Columns")}
                  </Text>
                  <Text as="p" tone="subdued">
                    {t("sheets.columns_help", "Each order becomes one row with these columns, in this order.")}
                  </Text>
                </BlockStack>
                <SortableList
                  items={columns}
                  getKey={(key) => key}
                  onReorder={(from, to) => setConfig((current) => ({ ...current, columns: moveItem(current.columns, from, to) }))}
                  renderItem={(key) => (
                    <InlineStack align="space-between" blockAlign="center" gap="200" wrap={false}>
                      <Text as="span">{columnLabel(key)}</Text>
                      <Button
                        variant="plain"
                        tone="critical"
                        disabled={columns.length <= 1}
                        onClick={() => setConfig((current) => ({ ...current, columns: current.columns.filter((column) => column !== key) }))}
                      >
                        {t("sheets.remove_column", "Remove")}
                      </Button>
                    </InlineStack>
                  )}
                />
                {available.length > 0 && (
                  <BlockStack gap="200">
                    <Text as="h3" variant="headingSm">
                      {t("sheets.add_columns", "Add columns")}
                    </Text>
                    <InlineGrid columns={{ xs: 2, sm: 3, md: 4 }} gap="200">
                      {available.map((key) => (
                        <Checkbox
                          key={key}
                          label={columnLabel(key)}
                          checked={false}
                          onChange={() => setConfig((current) => ({ ...current, columns: [...current.columns, key] }))}
                        />
                      ))}
                    </InlineGrid>
                  </BlockStack>
                )}
                <InlineStack gap="200" blockAlign="end" wrap>
                  <div style={{ flex: "1 1 220px" }}>
                    <TextField
                      label={t("sheets.custom_column", "Custom field key")}
                      value={customKey}
                      onChange={setCustomKey}
                      placeholder="cf_ab12cd34"
                      helpText={t("sheets.custom_column_help", "The key of a custom field from Form designer.")}
                      autoComplete="off"
                    />
                  </div>
                  <Button onClick={addCustom} disabled={!/^cf_[a-z0-9]{8}$/.test(customKey.trim())}>
                    {t("common.add", "Add")}
                  </Button>
                </InlineStack>
              </BlockStack>
            </Card>
          </>
        )}
      </Gate>
    </Screen>
  );
};

export default GoogleSheetsPage;
