import React, {
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import {
  Page,
  Card,
  BlockStack,
  Text,
  Checkbox,
  TextField,
  Select,
  Button,
  Banner,
  InlineStack,
  Box,
  Badge,
  Collapsible,
} from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";
import I18n from "../i18n-lang";
import { navigateTo } from "../../utils/navigate";

const HOUR_OPTIONS = Array.from({ length: 24 }, (_, i) => ({
  label: String(i).padStart(2, "0"),
  value: String(i),
}));

const MINUTE_OPTIONS = Array.from({ length: 60 }, (_, i) => ({
  label: String(i).padStart(2, "0"),
  value: String(i),
}));

const WEEKDAY_OPTIONS = [0, 1, 2, 3, 4, 5, 6].map((w) => ({
  labelKey: `reports.weekday_${w}`,
  value: String(w),
}));

const KIND_HELP = {
  delivery_status_ratio: "reports.kind_help_delivery",
  abandoned_cart_messages: "reports.kind_help_abandoned",
  preorder_otp_cart_csv_24h: "reports.kind_help_preorder",
  custom_sql: "reports.kind_help_custom_merchant",
};

const BUILTIN_REPORT_KINDS = new Set([
  "delivery_status_ratio",
  "abandoned_cart_messages",
  "preorder_otp_cart_csv_24h",
]);

const TIMEZONE_SHOP_DEFAULT = "__shop_default__";

/** Match ScheduledShopReport.extract_iana_from_shop_timezone — IANA tail after last ")". */
function defaultIanaTimezone(shop) {
  const raw = shop?.owner_timezone;
  if (raw == null || raw === "") return "UTC";
  const tail = String(raw).split(")").pop()?.trim();
  return tail || "UTC";
}

const FALLBACK_IANA_TIMEZONES = [
  "UTC",
  "Africa/Cairo",
  "Africa/Johannesburg",
  "America/Argentina/Buenos_Aires",
  "America/Bogota",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Mexico_City",
  "America/New_York",
  "America/Sao_Paulo",
  "America/Toronto",
  "America/Vancouver",
  "Asia/Bangkok",
  "Asia/Dubai",
  "Asia/Hong_Kong",
  "Asia/Jakarta",
  "Asia/Kolkata",
  "Asia/Seoul",
  "Asia/Shanghai",
  "Asia/Singapore",
  "Asia/Tokyo",
  "Australia/Melbourne",
  "Australia/Sydney",
  "Europe/Amsterdam",
  "Europe/Berlin",
  "Europe/Brussels",
  "Europe/Istanbul",
  "Europe/London",
  "Europe/Madrid",
  "Europe/Paris",
  "Europe/Warsaw",
  "Pacific/Auckland",
  "Pacific/Fiji",
  "Pacific/Honolulu",
];

function ianaTimeZoneIds() {
  if (typeof Intl !== "undefined" && typeof Intl.supportedValuesOf === "function") {
    try {
      return Intl.supportedValuesOf("timeZone");
    } catch {
      /* ignore */
    }
  }
  return FALLBACK_IANA_TIMEZONES;
}

function buildTimezoneSelectOptions(shop, extraSavedZones) {
  const ids = new Set(ianaTimeZoneIds());
  (extraSavedZones || []).forEach((z) => {
    const t = z?.trim();
    if (t) ids.add(t);
  });
  const sorted = [...ids].sort((a, b) => a.localeCompare(b));
  const def = defaultIanaTimezone(shop);
  return [
    {
      label: I18n.t("reports.timezone_shop_default", { zone: def }),
      value: TIMEZONE_SHOP_DEFAULT,
    },
    ...sorted.map((z) => ({ label: z, value: z })),
  ];
}

function displayRecipients(row, shop) {
  const saved = row.recipientEmails?.trim();
  if (saved) return row.recipientEmails;
  return shop?.owner_email || "";
}

/** Daily vs weekly is admin-defined (read-only). */
function cadenceFromAdmin(row) {
  if ((row.scheduleFrequency ?? "daily") === "weekly") {
    return I18n.t("reports.admin_cadence_weekly");
  }
  return I18n.t("reports.admin_cadence_daily");
}

export default function ReportsPage() {
  const { shop: [shop] } = useContext(StoreContext);
  const [reports, setReports] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setErrorMsg] = useState("");
  const [savingId, setSavingId] = useState(null);
  const [sendNowId, setSendNowId] = useState(null);
  const [sendNowBanner, setSendNowBanner] = useState("");
  /** Collapsible open only when explicitly true; all cards start collapsed. */
  const [expandedById, setExpandedById] = useState({});

  const load = useCallback(async () => {
    if (!shop?.id) return;
    setLoading(true);
    setErrorMsg("");
    try {
      const { data } = await Api.get("/scheduled_shop_reports");
      setReports(Array.isArray(data) ? data : []);
    } catch (e) {
      const fromServer =
        e.response?.data?.errors?.join?.(", ") ||
        e.response?.data?.error ||
        e.response?.data?.exception;
      const detail = [fromServer, e.response?.status ? `HTTP ${e.response.status}` : null]
        .filter(Boolean)
        .join(" — ");
      setErrorMsg(
        detail
          ? `${I18n.t("reports.load_error")} ${detail}`
          : I18n.t("reports.load_error"),
      );
    } finally {
      setLoading(false);
    }
  }, [shop?.id]);

  useEffect(() => {
    load();
  }, [load]);

  const timezoneSelectOptions = useMemo(
    () =>
      buildTimezoneSelectOptions(
        shop,
        reports.map((r) => r.timezone).filter(Boolean),
      ),
    [shop, reports],
  );

  const persist = async (id, payload, { collapseAfter = false } = {}) => {
    setSavingId(id);
    setErrorMsg("");
    try {
      const { data } = await Api.patch(`/scheduled_shop_reports/${id}`, {
        scheduledShopReport: payload,
      });
      setReports((prev) => prev.map((r) => (r.id === id ? { ...r, ...data } : r)));
      if (collapseAfter) {
        setExpandedById((prev) => ({ ...prev, [id]: false }));
      }
    } catch (e) {
      const msg =
        e.response?.data?.errors?.join?.(", ") ||
        e.message ||
        I18n.t("reports.save_error");
      setErrorMsg(msg);
    } finally {
      setSavingId(null);
    }
  };

  const patchRow = (id, updates) => {
    setReports((prev) =>
      prev.map((r) => ( r.id === id ? { ...r, ...updates } : r)),
    );
  };

  const saveRow = (row) => {
    const isWeekly = (row.scheduleFrequency ?? "daily") === "weekly";
    const base = {
      enabled: row.enabled,
      sendHour: row.sendHour ?? 8,
      sendMinute: row.sendMinute ?? 0,
      weeklySendWday: isWeekly ? (row.weeklySendWday ?? 1) : null,
      timezone: row.timezone,
      recipientEmails: row.recipientEmails,
    };
    persist(row.id, base, { collapseAfter: true });
  };

  const queueSendNow = async (row) => {
    setSendNowId(row.id);
    setErrorMsg("");
    setSendNowBanner("");
    try {
      const { data } = await Api.post(`/scheduled_shop_reports/${row.id}/send_now`);
      setSendNowBanner(data?.message || I18n.t("reports.send_now_queued"));
    } catch (e) {
      const msg =
        e.response?.data?.errors?.join?.(", ") ||
        e.message ||
        I18n.t("reports.send_now_error");
      setErrorMsg(msg);
    } finally {
      setSendNowId(null);
    }
  };

  const handleToggle = (row, enabled) => {
    patchRow(row.id, { enabled });
    persist(row.id, { enabled }, { collapseAfter: false });
  };

  const builtinBadge = (kind) => {
    if (!BUILTIN_REPORT_KINDS.has(kind)) return null;
    return <Badge>{I18n.t("reports.badge_builtin")}</Badge>;
  };

  if (loading) {
    return (
      <Page title={I18n.t("reports.title")}>
        <Card>
          <Box padding="300">
            <Text as="p" variant="bodySm">
              {I18n.t("reports.loading")}
            </Text>
          </Box>
        </Card>
      </Page>
    );
  }

  return (
    <Page
      title={I18n.t("reports.title")}
      subtitle={I18n.t("reports.subtitle")}
      backAction={{
        content: I18n.t("reports.back_home"),
        onAction: () => navigateTo("/"),
      }}
    >
      <BlockStack gap="200">
        {error ? (
          <Banner tone="critical" onDismiss={() => setErrorMsg("")}>
            <Text as="p" variant="bodySm">
              {error}
            </Text>
          </Banner>
        ) : null}

        {sendNowBanner ? (
          <Banner tone="success" onDismiss={() => setSendNowBanner("")}>
            <Text as="p" variant="bodySm">
              {sendNowBanner}
            </Text>
          </Banner>
        ) : null}

        {reports.map((row) => {
          const collapsibleOpen = expandedById[row.id] === true;
          const isWeekly = (row.scheduleFrequency ?? "daily") === "weekly";

          return (
            <Card key={row.id}>
              <Box padding={collapsibleOpen ? "300" : "150"}>
                <BlockStack gap={collapsibleOpen ? "200" : "100"}>
                  <InlineStack
                    align="space-between"
                    blockAlign="center"
                    gap="200"
                  >
                    <InlineStack gap="150" blockAlign="center" wrap={false}>
                      <Text variant="headingSm" as="h2">
                        {row.name}
                      </Text>
                      {builtinBadge(row.reportKind)}
                    </InlineStack>
                    <Box minWidth="0">
                      <Checkbox
                        label={I18n.t("reports.enabled")}
                        checked={!!row.enabled}
                        onChange={(v) => handleToggle(row, v)}
                        disabled={savingId === row.id}
                      />
                    </Box>
                  </InlineStack>

                  <Text as="p" variant="bodySm" tone="subdued">
                    {cadenceFromAdmin(row)}
                  </Text>

                  {row.defaultSubscribeAll ? (
                    <Text as="p" variant="bodySm" tone="subdued">
                      {I18n.t("reports.default_subscribe_banner")}
                    </Text>
                  ) : null}

                  {collapsibleOpen ? (
                    <Text as="p" variant="bodySm" tone="subdued">
                      {I18n.t(
                        KIND_HELP[row.reportKind] ||
                          "reports.kind_help_custom_merchant",
                      )}
                    </Text>
                  ) : null}

                  {collapsibleOpen && row.merchantDescription?.trim() ? (
                    <Box paddingBlockStart="100">
                      <Text as="p" variant="bodySm" fontWeight="medium">
                        {I18n.t("reports.merchant_description_label")}
                      </Text>
                      <Text as="p" variant="bodySm" tone="subdued">
                        {row.merchantDescription.trim()}
                      </Text>
                    </Box>
                  ) : null}

                  <Button
                    variant="tertiary"
                    size="slim"
                    disclosure={collapsibleOpen ? "up" : "down"}
                    textAlign="left"
                    onClick={() =>
                      setExpandedById((prev) => ({
                        ...prev,
                        [row.id]: !collapsibleOpen,
                      }))
                    }
                  >
                    {I18n.t("reports.delivery_settings")}
                  </Button>
                  <Collapsible
                    open={collapsibleOpen}
                    id={`scheduled-report-${row.id}-settings`}
                  >
                    <Box paddingBlockStart="200">
                      <BlockStack gap="300">
                        <InlineStack gap="300" wrap={false}>
                          <Select
                            label={I18n.t("reports.send_hour")}
                            options={HOUR_OPTIONS}
                            value={String(row.sendHour ?? 8)}
                            onChange={(v) =>
                              patchRow(row.id, { sendHour: Number(v) })
                            }
                          />
                          <Select
                            label={I18n.t("reports.send_minute")}
                            options={MINUTE_OPTIONS}
                            value={String(row.sendMinute ?? 0)}
                            onChange={(v) =>
                              patchRow(row.id, { sendMinute: Number(v) })
                            }
                          />
                        </InlineStack>

                        {isWeekly ? (
                          <Select
                            label={I18n.t("reports.weekly_send_day")}
                            options={WEEKDAY_OPTIONS.map((o) => ({
                              label: I18n.t(o.labelKey),
                              value: o.value,
                            }))}
                            value={String(
                              row.weeklySendWday != null ? row.weeklySendWday : 1,
                            )}
                            onChange={(v) =>
                              patchRow(row.id, {
                                weeklySendWday: Number(v),
                              })
                            }
                          />
                        ) : null}

                        <Select
                          label={I18n.t("reports.timezone")}
                          options={timezoneSelectOptions}
                          value={
                            row.timezone?.trim()
                              ? row.timezone.trim()
                              : TIMEZONE_SHOP_DEFAULT
                          }
                          onChange={(v) =>
                            patchRow(row.id, {
                              timezone:
                                v === TIMEZONE_SHOP_DEFAULT ? "" : v,
                            })
                          }
                          helpText={I18n.t("reports.timezone_help")}
                        />

                        <TextField
                          label={I18n.t("reports.recipients")}
                          value={displayRecipients(row, shop)}
                          onChange={(v) =>
                            patchRow(row.id, { recipientEmails: v })
                          }
                          autoComplete="off"
                          helpText={I18n.t("reports.recipients_help")}
                        />

                        <Text as="p" variant="bodySm" tone="subdued">
                          {row.outputFormat === "csv_attachment"
                            ? I18n.t("reports.format_csv")
                            : I18n.t("reports.format_summary")}
                        </Text>

                        <InlineStack gap="200" blockAlign="center" wrap>
                          <Button
                            variant="primary"
                            size="slim"
                            onClick={() =>
                              saveRow(
                                reports.find((r) => r.id === row.id) || row,
                              )
                            }
                            loading={savingId === row.id}
                          >
                            {I18n.t("reports.save_now")}
                          </Button>
                          <Button
                            size="slim"
                            onClick={() =>
                              queueSendNow(
                                reports.find((r) => r.id === row.id) || row,
                              )
                            }
                            loading={sendNowId === row.id}
                            disabled={!row.enabled}
                          >
                            {I18n.t("reports.send_now")}
                          </Button>
                          {row.lastSentOn ? (
                            <Text as="span" variant="bodySm" tone="subdued">
                              {I18n.t("reports.last_sent", {
                                date: row.lastSentOn,
                              })}
                            </Text>
                          ) : null}
                        </InlineStack>
                      </BlockStack>
                    </Box>
                  </Collapsible>
                </BlockStack>
              </Box>
            </Card>
          );
        })}
      </BlockStack>
    </Page>
  );
}
