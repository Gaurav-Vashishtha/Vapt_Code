import React, { useCallback, useEffect, useMemo, useState } from "react";

// Local error boundary so a bug in this card never takes down the rest of the
// prepaid settings page. Render-time crashes (e.g. a Polaris internal calling
// .map on an unexpected prop shape) get caught here, logged to the console,
// and replaced with a clean fallback Card.
class PrepaidRemindersBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }
  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }
  componentDidCatch(error, info) {
    // eslint-disable-next-line no-console
    console.error("[PrepaidReminders] render failed:", error, info?.componentStack);
  }
  render() {
    if (this.state.hasError) return null;
    return this.props.children;
  }
}

import {
  Card,
  Box,
  BlockStack,
  InlineStack,
  Text,
  Button,
  Badge,
  Banner,
  Modal,
  TextField,
  Select,
  Checkbox,
  Spinner,
  Divider,
  EmptyState,
} from "@shopify/polaris";
import useApi from "../Hooks/useApi";
import I18n from "../i18n-lang";

const SUPPORTED_LANGUAGES = [
  { get label() {
      return I18n.t("prepaid_reminders.english_en");
    }, value: "en" },
  { get label() {
      return I18n.t("prepaid_reminders.hindi_hi");
    }, value: "hi" },
  { get label() {
      return I18n.t("prepaid_reminders.spanish_es");
    }, value: "es" },
  { get label() {
      return I18n.t("prepaid_reminders.french_fr");
    }, value: "fr" },
  { get label() {
      return I18n.t("prepaid_reminders.arabic_ar");
    }, value: "ar" },
];

const DISCOUNT_TYPES = [
  { get label() {
      return I18n.t("prepaid_reminders.fixed");
    }, value: "FIXED" },
  { get label() {
      return I18n.t("prepaid_reminders.percentage");
    }, value: "PERCENTAGE" },
];

const UNIT_OPTIONS = [
  { label: "minutes", value: "minutes" },
  { label: "hours", value: "hours" },
  { label: "days", value: "days" },
];

// Convert minutes → {value, unit} for cleaner editing, and back on save.
const minutesToDelay = (mins) => {
  if (!mins) return { value: 30, unit: "minutes" };
  if (mins % 1440 === 0) return { value: mins / 1440, unit: "days" };
  if (mins % 60 === 0) return { value: mins / 60, unit: "hours" };
  return { value: mins, unit: "minutes" };
};
const delayToMinutes = (value, unit) => {
  const n = Number(value) || 0;
  if (unit === "days") return n * 1440;
  if (unit === "hours") return n * 60;
  return n;
};

const uuid = () =>
  "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });

// Reverse-map a raw MSG91 template name (what's stored in
// setting.whatsapp_prepaid_template_name) to the friendly library label so
// the merchant never sees the operator-side name. Returns null if no library
// entry matches.
const friendlyShopDefaultTemplate = (templates, msg91Name) => {
  if (!msg91Name) return null;
  const hit = templates.find((t) => t.msg91TemplateName === msg91Name);
  return hit ? hit.name : null;
};

const summarize = (r, templates, shopDefaults) => {
  const dly = minutesToDelay(r.delayMinutes);
  const range =
    r.cartMin == null && r.cartMax == null
      ? "all carts"
      : `${r.cartMin == null ? "≤" : `${r.cartMin}`}${
          r.cartMin != null && r.cartMax != null ? " – " : r.cartMax != null ? " ≤ " : "+"
        }${r.cartMax == null ? "" : r.cartMax}`;
  const discount =
    r.discount != null
      ? `${r.discount} ${r.discountType || shopDefaults.discountType || "FIXED"}`
      : `default (${shopDefaults.discount || "—"})`;
  const tpl = templates.find((t) => t.key === r.templateKey);
  const friendlyDefault = friendlyShopDefaultTemplate(templates, shopDefaults.templateKey);
  const tplLabel = tpl
    ? tpl.name
    : r.templateKey || (friendlyDefault ? `default (${friendlyDefault})` : "default template");
  const lang = r.language || shopDefaults.language || "en";
  return `${dly.value} ${dly.unit} after order · ${range} · ${discount} off · ${tplLabel} (${lang})`;
};

const TemplatePicker = ({ value, templates, onChange }) => {
  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))",
        gap: 12,
      }}
    >
      {templates.map((t) => (
        <div
          key={t.key}
          role="button"
          tabIndex={0}
          onClick={() => onChange(t.key)}
          onKeyDown={(e) => (e.key === "Enter" || e.key === " ") && onChange(t.key)}
          style={{
            border: value === t.key ? "2px solid #008060" : "1px solid #e1e3e5",
            borderRadius: 8,
            padding: 8,
            cursor: "pointer",
            background: value === t.key ? "#f1f8f5" : "#ffffff",
          }}
        >
          <img
            src={t.previewImageUrl}
            alt={t.name}
            style={{ width: "100%", borderRadius: 4, display: "block" }}
          />
          <div style={{ marginTop: 6 }}>
            <Text as="span" variant="bodyMd" fontWeight="medium">
              {t.name}
            </Text>
          </div>
          <Text as="p" tone="subdued" variant="bodySm">
            {t.description}
          </Text>
        </div>
      ))}
      {templates.length === 0 && (
        <Text tone="subdued" as="p" variant="bodySm">
          {I18n.t("prepaid_reminders.no_templates_configured")}
        </Text>
      )}
    </div>
  );
};

const ReminderEditor = ({ reminder, templates, bspTemplates = [], shopDefaults, onSave, onCancel }) => {
  const dly = minutesToDelay(reminder.delayMinutes);
  const [label, setLabel] = useState(reminder.label || "");
  const [delayValue, setDelayValue] = useState(String(dly.value));
  const [delayUnit, setDelayUnit] = useState(dly.unit);
  const [cartMin, setCartMin] = useState(reminder.cartMin == null ? "" : String(reminder.cartMin));
  const [cartMax, setCartMax] = useState(reminder.cartMax == null ? "" : String(reminder.cartMax));
  const [useDiscount, setUseDiscount] = useState(reminder.discount != null);
  const [discount, setDiscount] = useState(reminder.discount == null ? "" : String(reminder.discount));
  const [discountType, setDiscountType] = useState(reminder.discountType || "FIXED");
  const [addShipping, setAddShipping] = useState(
    reminder.addShipping === true || reminder.add_shipping === true,
  );
  const [useTemplate, setUseTemplate] = useState(!!reminder.templateKey);
  const [templateKey, setTemplateKey] = useState(reminder.templateKey || "");
  const [useLanguage, setUseLanguage] = useState(!!reminder.language);
  const [language, setLanguage] = useState(reminder.language || "en");
  const [bspTemplateId, setBspTemplateId] = useState(reminder.bspTemplateId || "");
  const [enabled, setEnabled] = useState(reminder.enabled !== false);
  const [localError, setLocalError] = useState("");

  const handleSave = () => {
    setLocalError("");
    const minutes = delayToMinutes(delayValue, delayUnit);
    if (!(minutes > 0)) return setLocalError("Delay must be greater than 0.");
    const cMin = cartMin === "" ? null : Number(cartMin);
    const cMax = cartMax === "" ? null : Number(cartMax);
    if (cMin != null && cMin < 0) return setLocalError("Cart min cannot be negative.");
    if (cMin != null && cMax != null && cMax <= cMin)
      return setLocalError("Cart max must be greater than cart min.");
    if (useDiscount && !(Number(discount) >= 0))
      return setLocalError("Discount must be a non-negative number.");
    if (useTemplate && !templateKey) return setLocalError("Pick a template or uncheck the override.");

    onSave({
      ...reminder,
      label: label || null,
      enabled,
      delayMinutes: minutes,
      cartMin: cMin,
      cartMax: cMax,
      discount: useDiscount ? Number(discount) : null,
      discountType: useDiscount ? discountType : null,
      addShipping,
      templateKey: useTemplate ? templateKey : null,
      language: useLanguage ? language : null,
      bspTemplateId: bspTemplateId || null,
    });
  };

  return (
    <Modal
      open
      onClose={onCancel}
      title={reminder.id ? `Edit reminder${label ? ` — ${label}` : ""}` : "Add reminder"}
      primaryAction={{ content: I18n.t("prepaid_reminders.save"), onAction: handleSave }}
      secondaryActions={[{ content: I18n.t("prepaid_reminders.cancel"), onAction: onCancel }]}
    >
      <Modal.Section>
        <BlockStack gap="400">
          {localError && <Banner tone="critical">{localError}</Banner>}

          <TextField label={I18n.t("prepaid_reminders.label_optional")} value={label} onChange={setLabel} autoComplete="off" />

          <Checkbox label={I18n.t("prepaid_reminders.enabled")} checked={enabled} onChange={setEnabled} />

          <Divider />

          <Text as="h3" variant="headingSm">{I18n.t("prepaid_reminders.trigger")}</Text>
          <InlineStack gap="200" blockAlign="center" wrap={false}>
            <Box minWidth="120px">
              <TextField
                label={I18n.t("prepaid_reminders.delay")}
                type="number"
                value={delayValue}
                onChange={setDelayValue}
                autoComplete="off"
              />
            </Box>
            <Box minWidth="160px">
              <Select label={I18n.t("prepaid_reminders.unit")} options={UNIT_OPTIONS} value={delayUnit} onChange={setDelayUnit} />
            </Box>
          </InlineStack>

          <Divider />

          <Text as="h3" variant="headingSm">{I18n.t("prepaid_reminders.cart_range_optional")}</Text>
          <InlineStack gap="200" blockAlign="end" wrap={false}>
            <Box minWidth="160px">
              <TextField
                label={I18n.t("prepaid_reminders.min_blank_no_floor")}
                type="number"
                value={cartMin}
                onChange={setCartMin}
                autoComplete="off"
              />
            </Box>
            <Box minWidth="160px">
              <TextField
                label={I18n.t("prepaid_reminders.max_blank_no_cap")}
                type="number"
                value={cartMax}
                onChange={setCartMax}
                autoComplete="off"
              />
            </Box>
          </InlineStack>

          <Divider />

          <Text as="h3" variant="headingSm">{I18n.t("prepaid_reminders.discount_override")}</Text>
          <Checkbox
            label={`Override shop default (${shopDefaults.discount || "—"} ${shopDefaults.discountType || ""})`}
            checked={useDiscount}
            onChange={setUseDiscount}
          />
          {useDiscount && (
            <InlineStack gap="200" blockAlign="end" wrap={false}>
              <Box minWidth="160px">
                <TextField
                  label={I18n.t("prepaid_reminders.discount")}
                  type="number"
                  value={discount}
                  onChange={setDiscount}
                  autoComplete="off"
                />
              </Box>
              <Box minWidth="160px">
                <Select
                  label={I18n.t("prepaid_reminders.type")}
                  options={DISCOUNT_TYPES}
                  value={discountType}
                  onChange={setDiscountType}
                />
              </Box>
            </InlineStack>
          )}

          <Checkbox
            label={I18n.t("prepaid_reminders.also_waive_shipping")}
            helpText={I18n.t("prepaid_reminders.if_the_shopify_order_has_a")}
            checked={addShipping}
            onChange={setAddShipping}
          />

          <Divider />

          <Text as="h3" variant="headingSm">{I18n.t("prepaid_reminders.language_override")}</Text>
          <Checkbox
            label={`Override shop default (${shopDefaults.language || "en"})`}
            checked={useLanguage}
            onChange={(v) => {
              setUseLanguage(v);
              if (!v) setLanguage(shopDefaults.language || "en");
            }}
          />
          {useLanguage && (
            <Select
              label={I18n.t("prepaid_reminders.language")}
              options={SUPPORTED_LANGUAGES}
              value={language}
              onChange={setLanguage}
            />
          )}

          <Divider />

          <Text as="h3" variant="headingSm">{I18n.t("prepaid_reminders.template_override")}</Text>
          <Checkbox
            label={`Override shop default${
              friendlyShopDefaultTemplate(templates, shopDefaults.templateKey)
                ? ` (${friendlyShopDefaultTemplate(templates, shopDefaults.templateKey)})`
                : ""
            }`}
            checked={useTemplate}
            onChange={setUseTemplate}
          />
          {useTemplate && (
            <TemplatePicker
              value={templateKey}
              templates={templates}
              onChange={setTemplateKey}
            />
          )}

          {bspTemplates.length > 0 && (
            <>
              <Divider />
              <Text as="h3" variant="headingSm">{I18n.t("prepaid_reminders.own_whatsapp_bsp_template")}</Text>
              <Text tone="subdued" as="p" variant="bodySm">
                {I18n.t("prepaid_reminders.send_this_reminder_from_your_own")}
              </Text>
              <Select
                label={I18n.t("prepaid_reminders.bsp_template")}
                options={[
                  { label: I18n.t("prepaid_reminders.use_msg91_shop_default"), value: "" },
                  ...bspTemplates.map((t) => ({ label: `${t.name} (${t.language})`, value: String(t.id) })),
                ]}
                value={bspTemplateId ? String(bspTemplateId) : ""}
                onChange={(v) => setBspTemplateId(v ? Number(v) : "")}
              />
            </>
          )}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

// Coerce whatever the reminders endpoint returns into a plain array. The
// jsonb column can come back double-encoded as a JSON string (e.g. "[]"),
// in which case Array.isArray is false and the card would hang on "Loading…"
// forever. Parse the string form, and fall back to [] for anything unusable.
const asReminderArray = (val) => {
  if (Array.isArray(val)) return val;
  if (typeof val === "string") {
    try {
      const parsed = JSON.parse(val);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
};

const PrepaidReminders = ({ shopDefaults }) => {
  const [{ data: tplData, error: tplError }] = useApi(
    { url: "/api/prepaid_templates", method: "GET" },
    { manual: false }
  );
  const [{ data: remData, error: remError }, refetchReminders] = useApi(
    { url: "/api/prepaid_reminders", method: "GET" },
    { manual: false }
  );
  const [, saveApi] = useApi(
    { url: "/api/prepaid_reminders", method: "PATCH" },
    { manual: true }
  );
  const [{ data: bspData }] = useApi(
    { url: "/api/whatsapp/templates", method: "GET" },
    { manual: false }
  );

  const [editing, setEditing] = useState(null); // reminder being edited (or new blank)
  const [working, setWorking] = useState(null); // local snapshot of the array we're editing
  const [saveState, setSaveState] = useState({ saving: false, error: "", success: "" });

  // Always coerce to an array — handles backend rollouts where the endpoint
  // may return null, an error, or a different shape on stale dynos.
  const templates = Array.isArray(tplData?.entries) ? tplData.entries : [];
  const bspTemplates = Array.isArray(bspData?.templates)
    ? bspData.templates.filter((t) => t.status === "approved")
    : [];

  // Hide the section entirely when the API isn't available (e.g. stale slug,
  // route not deployed). Avoids "B.map is not a function" further down the
  // tree and keeps the rest of the prepaid settings page usable.
  const endpointMissing =
    (tplError && tplError?.response?.status === 404) ||
    (remError && remError?.response?.status === 404);

  // Seed local working state from server response. Resolve as soon as the
  // request settles: on success, coerce the payload to an array (handles the
  // double-encoded "[]" string case); on a non-404 error, seed an empty list
  // so the card renders its empty state instead of spinning indefinitely.
  useEffect(() => {
    if (working != null) return;
    if (remData) setWorking(asReminderArray(remData.reminders));
    else if (remError) setWorking([]);
  }, [remData, remError, working]);

  if (endpointMissing) return null;

  const reminders = working || [];
  const dirty = useMemo(
    () => JSON.stringify(reminders) !== JSON.stringify(asReminderArray(remData?.reminders)),
    [reminders, remData]
  );

  const handleAdd = () => {
    setEditing({
      id: null,
      enabled: true,
      label: "",
      delayMinutes: 30,
      cartMin: null,
      cartMax: null,
      discount: null,
      discountType: null,
      templateKey: null,
      language: null,
    });
  };

  const handleEdit = (r) => setEditing(r);

  const handleSaveReminder = (updated) => {
    const withId = { ...updated, id: updated.id || uuid() };
    setWorking((prev) => {
      const list = prev ? [...prev] : [];
      const idx = list.findIndex((r) => r.id === withId.id);
      if (idx >= 0) list[idx] = withId;
      else list.push(withId);
      return list;
    });
    setEditing(null);
  };

  const handleDelete = (id) => {
    setWorking((prev) => (prev || []).filter((r) => r.id !== id));
  };

  const handlePersist = async () => {
    setSaveState({ saving: true, error: "", success: "" });
    try {
      const { data } = await saveApi({ data: { reminders } });
      setWorking(asReminderArray(data.reminders));
      setSaveState({ saving: false, error: "", success: "Saved" });
      setTimeout(() => setSaveState((s) => ({ ...s, success: "" })), 2000);
    } catch (err) {
      setSaveState({
        saving: false,
        error: err?.response?.data?.error || err?.message || "Save failed",
        success: "",
      });
    }
  };

  if (working == null) {
    return (
      <Card>
        <Box padding="400">
          <InlineStack gap="200" align="center">
            <Spinner size="small" />
            <Text as="span">{I18n.t("prepaid_reminders.loading_reminders")}</Text>
          </InlineStack>
        </Box>
      </Card>
    );
  }

  return (
    <Card>
      <Box padding="400">
        <BlockStack gap="400">
          <InlineStack align="space-between" blockAlign="center">
            <BlockStack gap="050">
              <Text as="h2" variant="headingMd">
                {I18n.t("prepaid_reminders.prepaid_reminders")}
              </Text>
              <Text tone="subdued" as="p" variant="bodySm">
                {I18n.t("prepaid_reminders.each_new_cod_order_fires_every")}
              </Text>
            </BlockStack>
            <Button variant="primary" onClick={handleAdd}>
              {I18n.t("prepaid_reminders.add_reminder")}
            </Button>
          </InlineStack>

          {saveState.error && <Banner tone="critical">{saveState.error}</Banner>}
          {saveState.success && <Banner tone="success">{saveState.success}</Banner>}

          {reminders.length === 0 ? (
            <Box padding="400">
              <EmptyState
                heading={I18n.t("prepaid_reminders.no_reminders_yet")}
                image="https://cdn.shopify.com/s/files/1/0262/4071/2726/files/emptystate-files.png"
              >
                <Text as="p" tone="subdued">
                  {I18n.t("prepaid_reminders.add_a_reminder_to_schedule_whatsapp")}
                </Text>
              </EmptyState>
            </Box>
          ) : (
            <BlockStack gap="200">
              {reminders.map((r) => (
                <Box
                  key={r.id}
                  padding="300"
                  borderColor="border"
                  borderWidth="025"
                  borderRadius="200"
                >
                  <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
                    <BlockStack gap="050">
                      <InlineStack gap="200" blockAlign="center">
                        <Text as="span" variant="bodyMd" fontWeight="semibold">
                          {r.label || "(no label)"}
                        </Text>
                        {r.enabled === false ? (
                          <Badge tone="critical">{I18n.t("prepaid_reminders.disabled")}</Badge>
                        ) : (
                          <Badge tone="success">{I18n.t("prepaid_reminders.enabled")}</Badge>
                        )}
                      </InlineStack>
                      <Text as="span" tone="subdued" variant="bodySm">
                        {summarize(r, templates, shopDefaults)}
                      </Text>
                    </BlockStack>
                    <InlineStack gap="100">
                      <Button variant="plain" onClick={() => handleEdit(r)}>
                        {I18n.t("prepaid_reminders.edit")}
                      </Button>
                      <Button variant="plain" tone="critical" onClick={() => handleDelete(r.id)}>
                        {I18n.t("prepaid_reminders.delete")}
                      </Button>
                    </InlineStack>
                  </InlineStack>
                </Box>
              ))}
            </BlockStack>
          )}

          {dirty && (
            <InlineStack align="end" gap="200">
              <Button onClick={() => setWorking(asReminderArray(remData?.reminders))}>{I18n.t("prepaid_reminders.discard_changes")}</Button>
              <Button variant="primary" loading={saveState.saving} onClick={handlePersist}>
                {I18n.t("prepaid_reminders.save_reminders")}
              </Button>
            </InlineStack>
          )}
        </BlockStack>
      </Box>

      {editing && (
        <ReminderEditor
          reminder={editing}
          templates={templates}
          bspTemplates={bspTemplates}
          shopDefaults={shopDefaults}
          onSave={handleSaveReminder}
          onCancel={() => setEditing(null)}
        />
      )}
    </Card>
  );
};

const PrepaidRemindersWithBoundary = (props) => (
  <PrepaidRemindersBoundary>
    <PrepaidReminders {...props} />
  </PrepaidRemindersBoundary>
);

export default PrepaidRemindersWithBoundary;
