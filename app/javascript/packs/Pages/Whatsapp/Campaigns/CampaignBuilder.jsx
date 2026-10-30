import React, { useState, useEffect, useMemo, useCallback, useRef } from "react";
import {
  Layout, Card, BlockStack, InlineStack, InlineGrid, Box, Text, Button, Badge, Banner, Select,
  TextField, ChoiceList, DropZone, Spinner, Divider, Modal, Checkbox, Collapsible, SkeletonBodyText,
  Icon,
} from "@shopify/polaris";
import { CircleTickMajor } from "@shopify/polaris-icons";
import WhatsappLayout from "../WhatsappLayout";
import { navigateTo } from "../../../../utils/navigate";
import { api, waitForImport } from "./api";
import MessagePreview, {
  componentOf, bodyPlaceholders, hasHeaderVariable, hasDynamicButton,
} from "./MessagePreview";
import { AudienceEditor } from "./AudiencesTab";
import RecipePicker from "./RecipePicker";
import { scheduleHelpText } from "./CampaignsTab";
import {
  t, paths, audienceChoices, audienceSourceLabel, describeFilters, fieldLabel, fieldOptions,
  suggestField, formatNumber, splitPhones,
} from "./copy";

const STEPS = () => [
  { id: 1, label: t("step_audience", "Audience") },
  { id: 2, label: t("step_message", "Message") },
  { id: 3, label: t("step_review", "Review and send") },
];

const CART_WINDOWS = () => [
  { label: t("window_7", "Last 7 days"), value: "7" },
  { label: t("window_3", "Last 3 days"), value: "3" },
  { label: t("window_30", "Last 30 days"), value: "30" },
  { label: t("window_all", "Any time"), value: "all" },
  { label: t("window_custom", "Choose dates"), value: "custom" },
];

const DEFAULT_SEND_POLICY = {
  quiet_hours: { enabled: true, start_hour: 21, end_hour: 9 },
  frequency_cap: { enabled: true, hours: 48 },
};

const policyFrom = (raw) => ({
  quiet_hours: { ...DEFAULT_SEND_POLICY.quiet_hours, ...(raw?.quiet_hours || {}) },
  frequency_cap: { ...DEFAULT_SEND_POLICY.frequency_cap, ...(raw?.frequency_cap || {}) },
});

const hourLabel = (hour) => new Date(2000, 0, 1, Number(hour)).toLocaleTimeString(undefined, { hour: "numeric" });

const HOUR_OPTIONS = () => Array.from({ length: 24 }, (_, h) => ({ label: hourLabel(h), value: String(h) }));

// Abandoned-cart rules the date picker doesn't show (set by recipes); kept so a save doesn't drop them.
const CART_EXTRA_KEYS = ["exclude_recovered", "exclude_recent_automation_hours"];

const formatMoney = (amount, currency, digits = 0) => {
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency", currency, minimumFractionDigits: digits, maximumFractionDigits: digits,
    }).format(Number(amount || 0));
  } catch (_) {
    return `${currency} ${Number(amount || 0).toFixed(digits)}`;
  }
};

const isoDaysAgo = (days) => {
  const d = new Date();
  d.setDate(d.getDate() - Number(days));
  return d.toISOString().slice(0, 10);
};

const defaultName = () =>
  t("default_name", "Campaign %{date}", {
    date: new Date().toLocaleDateString(undefined, { day: "numeric", month: "short" }),
  });

const humanizeTemplate = (name) => {
  const s = String(name || "").replace(/_/g, " ").trim();
  return s ? s[0].toUpperCase() + s.slice(1) : s;
};

const templateSnippet = (template) => {
  const body = componentOf(template, "BODY")?.text || "";
  return body.length > 110 ? `${body.slice(0, 110).trim()}…` : body;
};

// The words around a variable, so "Blank 2" reads as "…your order {{2}} is on…".
const placeholderContext = (template, position) => {
  const body = componentOf(template, "BODY")?.text || "";
  const token = `{{${position}}}`;
  const i = body.indexOf(token);
  if (i < 0) return "";
  const before = body.slice(Math.max(0, i - 28), i).replace(/\{\{\d+\}\}/g, "…");
  const after = body.slice(i + token.length, i + token.length + 28).replace(/\{\{\d+\}\}/g, "…");
  return `${i > 28 ? "…" : ""}${before}${token}${after}${i + token.length + 28 < body.length ? "…" : ""}`;
};

// The date window an abandoned-cart campaign was saved with, as the picker value.
const windowFromFilter = (filter) => {
  if (!filter || filter.all) return "all";
  if (filter.date_from && !filter.date_to) {
    const days = Math.round((Date.now() - new Date(filter.date_from).getTime()) / 86400000);
    if (["3", "7", "30"].includes(String(days))) return String(days);
  }
  return filter.date_from || filter.date_to ? "custom" : "7";
};

const StepNav = ({ step, maxStep, onSelect }) => (
  <Card padding="300">
    <InlineStack gap="400" wrap>
      {STEPS().map((s) => {
        const done = s.id < step;
        const reachable = s.id <= maxStep;
        const current = s.id === step;
        return (
          <InlineStack key={s.id} gap="200" blockAlign="center" wrap={false}>
            {done ? (
              <Box minWidth="20px"><Icon source={CircleTickMajor} tone="success" /></Box>
            ) : (
              <div style={{ ...stepDot, ...(current ? stepDotCurrent : null) }}>{s.id}</div>
            )}
            {reachable && !current ? (
              <Button variant="plain" onClick={() => onSelect(s.id)}>{s.label}</Button>
            ) : (
              <Text as="span" fontWeight={current ? "semibold" : "regular"} tone={current ? undefined : "subdued"}>
                {s.label}
              </Text>
            )}
          </InlineStack>
        );
      })}
    </InlineStack>
  </Card>
);

const stepDot = {
  width: 20,
  height: 20,
  borderRadius: "50%",
  fontSize: 12,
  fontWeight: 600,
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  border: "1.5px solid var(--p-color-border)",
  color: "var(--p-color-text-secondary)",
};
const stepDotCurrent = { background: "var(--p-color-bg-fill-brand)", borderColor: "transparent", color: "var(--p-color-text-brand-on-bg-fill)" };

const TemplateOption = ({ template, selected, onSelect }) => (
  <div
    role="radio"
    aria-checked={selected}
    tabIndex={0}
    onClick={onSelect}
    onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onSelect(); } }}
    style={{
      cursor: "pointer",
      borderRadius: 10,
      padding: 12,
      border: selected ? "2px solid var(--p-color-border-emphasis)" : "1px solid var(--p-color-border)",
      background: selected ? "var(--p-color-bg-surface-selected)" : "var(--p-color-bg-surface)",
    }}
  >
    <BlockStack gap="100">
      <InlineStack align="space-between" gap="200" wrap={false}>
        <Text as="span" fontWeight="semibold">{humanizeTemplate(template.name)}</Text>
        <Badge>
          {(template.category || "").toUpperCase() === "MARKETING"
            ? t("category_marketing", "Promotion")
            : t("category_utility", "Update")}
        </Badge>
      </InlineStack>
      <Text as="p" variant="bodySm" tone="subdued">{templateSnippet(template)}</Text>
      {template.language && (
        <Text as="span" variant="bodySm" tone="subdued">{template.language}</Text>
      )}
    </BlockStack>
  </div>
);

const CampaignBuilder = ({ id }) => {
  const initialAudience = useMemo(() => new URLSearchParams(window.location.search).get("audience"), []);
  const initialRecipe = useMemo(() => new URLSearchParams(window.location.search).get("recipe"), []);

  const [loaded, setLoaded] = useState(!id && !initialRecipe);
  const [step, setStep] = useState(1);
  const [maxStep, setMaxStep] = useState(1);
  const [draftId, setDraftId] = useState(id || null);
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");

  // Audience
  const [name, setName] = useState(defaultName());
  const [source, setSource] = useState(initialAudience ? "segment" : "contacts");
  const [cartWindow, setCartWindow] = useState("7");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [contactsFilter, setContactsFilter] = useState({ all: true });
  const [cartExtras, setCartExtras] = useState({});
  const [segmentId, setSegmentId] = useState(initialAudience || "");
  const [segments, setSegments] = useState([]);
  const [creatingAudience, setCreatingAudience] = useState(false);
  const [importId, setImportId] = useState(null);
  const [importInfo, setImportInfo] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [preview, setPreview] = useState(null);
  const [previewing, setPreviewing] = useState(false);

  // Message
  const [accounts, setAccounts] = useState([]);
  const [accountId, setAccountId] = useState("");
  const [templates, setTemplates] = useState(null);
  const [templateId, setTemplateId] = useState("");
  const [mapping, setMapping] = useState({});
  const [defaults, setDefaults] = useState({});
  const [headerField, setHeaderField] = useState("");
  const [buttonField, setButtonField] = useState("");
  const [templatesVersion, setTemplatesVersion] = useState(0);
  const [recipeKey, setRecipeKey] = useState(initialRecipe);
  const [recipe, setRecipe] = useState(null);
  const [applyingRecipe, setApplyingRecipe] = useState(null);
  const [submittingTemplate, setSubmittingTemplate] = useState(false);

  // Review
  const [when, setWhen] = useState("now");
  const [scheduledAt, setScheduledAt] = useState("");
  const [scheduleTz, setScheduleTz] = useState(null);
  const [retryEnabled, setRetryEnabled] = useState(true);
  const [retryDelays, setRetryDelays] = useState(["6", "12"]);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [testPhones, setTestPhones] = useState("");
  const [testing, setTesting] = useState(false);
  const [testResults, setTestResults] = useState(null);
  const [confirmSend, setConfirmSend] = useState(false);
  const [sending, setSending] = useState(false);
  const [contactsTotal, setContactsTotal] = useState(null);
  const [sendPolicy, setSendPolicy] = useState(() => policyFrom(null));
  const [estimate, setEstimate] = useState(null);
  const [acknowledgeRisk, setAcknowledgeRisk] = useState(false);

  const draftRef = useRef(draftId);
  draftRef.current = draftId;
  const loadedOnce = useRef(false);
  const recipeStarted = useRef(false);

  // ── Loading ──────────────────────────────────────────────────────────

  const loadSegments = useCallback(async () => {
    try {
      const data = await api("/api/whatsapp/segments");
      setSegments(data.segments || []);
    } catch (_) { /* picker stays empty; creating one still works */ }
  }, []);

  useEffect(() => {
    loadSegments();
    api("/api/whatsapp/campaigns/overview")
      .then((o) => { setScheduleTz(o.schedule_timezone); setContactsTotal(o.contacts?.total ?? null); })
      .catch(() => {});
    api("/api/whatsapp/accounts")
      .then((data) => {
        const list = (data.accounts || []).filter((a) => a.ready_to_send);
        setAccounts(list);
        setAccountId((current) => current || String((list.find((a) => a.is_default) || list[0])?.id || ""));
      })
      .catch(() => {});
  }, [loadSegments]);

  // Existing draft: restore every field, then land on the first unfinished step.
  useEffect(() => {
    // A draft this page just created is already in state; reloading it would
    // throw away the step the merchant is on.
    if (!id || (String(id) === String(draftRef.current) && loadedOnce.current)) return;
    loadedOnce.current = true;
    (async () => {
      try {
        const data = await api(`/api/whatsapp/campaigns/${id}`);
        const c = data.campaign;
        if (c.status !== "draft") {
          navigateTo(paths.report(id));
          return;
        }
        setScheduleTz(data.schedule_timezone);
        setName(c.name || defaultName());
        setSource(c.audience_source || "contacts");
        const filter = c.audience_filter || {};
        if (c.audience_source === "abandoned_cart") {
          const w = windowFromFilter(filter);
          setCartWindow(w);
          if (w === "custom") { setDateFrom(filter.date_from || ""); setDateTo(filter.date_to || ""); }
          setCartExtras(Object.fromEntries(CART_EXTRA_KEYS.filter((k) => filter[k] !== undefined).map((k) => [k, filter[k]])));
        } else {
          setContactsFilter(filter.all || (!filter.date_from && !filter.date_to) ? { all: true } : filter);
        }
        setSegmentId(c.whatsapp_segment_id ? String(c.whatsapp_segment_id) : "");
        setImportId(c.whatsapp_audience_import_id || null);
        if (c.whatsapp_account_id) setAccountId(String(c.whatsapp_account_id));
        setTemplateId(c.template_id ? String(c.template_id) : "");
        setMapping(c.variable_mapping || {});
        setDefaults(c.variable_defaults || {});
        setHeaderField(c.header_field || "");
        setButtonField(c.button_field || "");
        setSendPolicy(policyFrom(c.send_policy));
        if (c.recipe_key) setRecipeKey(c.recipe_key);
        if (c.scheduled_at_input) { setWhen("later"); setScheduledAt(c.scheduled_at_input); }
        if (c.retry_config && c.retry_config.enabled !== undefined) {
          setRetryEnabled(!!c.retry_config.enabled);
          if (c.retry_config.delays_hours?.length) setRetryDelays(c.retry_config.delays_hours.map(String));
        }
        const landing = c.template_id ? 3 : 2;
        setStep(landing);
        setMaxStep(landing);
      } catch (e) { setError(e.message); } finally { setLoaded(true); }
    })();
  }, [id]);

  useEffect(() => {
    if (importId && !importInfo) {
      api(`/api/whatsapp/audience_imports/${importId}`).then(setImportInfo).catch(() => {});
    }
  }, [importId, importInfo]);

  useEffect(() => {
    if (!accountId && accounts.length) return;
    const qs = accountId ? `?account_id=${encodeURIComponent(accountId)}` : "";
    api(`/api/whatsapp/templates${qs}`)
      .then((data) =>
        setTemplates(
          (data.templates || []).filter(
            (tpl) => tpl.status === "approved" && ["MARKETING", "UTILITY"].includes((tpl.category || "").toUpperCase())
          )
        )
      )
      .catch((e) => { setError(e.message); setTemplates([]); });
  }, [accountId, accounts.length, templatesVersion]);

  const applyRecipe = useCallback(async (key) => {
    setApplyingRecipe(key);
    setError("");
    try {
      const res = await api(`/api/whatsapp/campaign_recipes/${encodeURIComponent(key)}/apply`, { method: "POST", body: {} });
      setRecipeKey(key);
      setDraftId(res.campaign_id);
      draftRef.current = res.campaign_id;
      loadedOnce.current = false;
      setLoaded(false);
      // Replace, not push: going back to /new?recipe= would create a second draft.
      window.history.replaceState({}, "", `${paths.edit(res.campaign_id)}?recipe=${encodeURIComponent(key)}`);
      window.dispatchEvent(new PopStateEvent("popstate"));
    } catch (e) {
      setError(e.message);
      setLoaded(true);
    } finally { setApplyingRecipe(null); }
  }, []);

  useEffect(() => {
    if (id || !initialRecipe || recipeStarted.current) return;
    recipeStarted.current = true;
    applyRecipe(initialRecipe);
  }, [id, initialRecipe, applyRecipe]);

  useEffect(() => {
    if (!recipeKey || templateId) return;
    const qs = accountId ? `?account_id=${encodeURIComponent(accountId)}` : "";
    api(`/api/whatsapp/campaign_recipes${qs}`)
      .then((data) => setRecipe((data.recipes || []).find((r) => r.key === recipeKey) || null))
      .catch(() => {});
  }, [recipeKey, accountId, templateId]);

  useEffect(() => {
    if (!recipe?.approved_template_id || templateId || !templates) return;
    const tpl = templates.find((x) => String(x.id) === String(recipe.approved_template_id));
    if (!tpl) return;
    setTemplateId(String(tpl.id));
    setMapping((m) => (Object.keys(m).length ? m : recipe.variable_mapping || {}));
    setDefaults((d) => (Object.keys(d).length ? d : recipe.variable_defaults || {}));
  }, [recipe, templates, templateId]);

  const submitRecipeTemplate = async () => {
    const payload = recipe?.template_payload;
    if (!payload) return;
    setSubmittingTemplate(true);
    setError("");
    try {
      // Meta won't reuse the name of a rejected or disabled template.
      const resubmit = recipe.template_status && recipe.template_status !== "pending";
      const name = resubmit ? `${payload.name_suggestion}_${Date.now().toString(36)}` : payload.name_suggestion;
      const qs = accountId ? `?account_id=${encodeURIComponent(accountId)}` : "";
      const res = await api(`/api/whatsapp/templates${qs}`, {
        method: "POST",
        body: {
          name,
          language: payload.language,
          category: payload.category,
          components: payload.components,
          event_type_key: payload.event_type_key,
          variable_mapping: payload.variable_mapping || {},
          url_button: payload.url_button || null,
        },
      });
      const status = res.template?.status || "pending";
      setRecipe((r) => ({
        ...r,
        template_status: status,
        approved_template_id: status === "approved" ? res.template.id : r.approved_template_id,
      }));
      if (status === "approved") setTemplatesVersion((v) => v + 1);
    } catch (e) { setError(e.message); } finally { setSubmittingTemplate(false); }
  };

  // ── Audience ─────────────────────────────────────────────────────────

  const filter = useMemo(() => {
    if (source === "abandoned_cart") {
      const range = cartWindow === "all"
        ? { all: true }
        : cartWindow === "custom"
          ? { date_from: dateFrom, date_to: dateTo }
          : { date_from: isoDaysAgo(cartWindow) };
      return { ...range, ...cartExtras };
    }
    return source === "contacts" ? contactsFilter : { all: true };
  }, [source, cartWindow, dateFrom, dateTo, contactsFilter, cartExtras]);

  const audienceReady =
    (source === "segment" && !!segmentId) ||
    (source === "csv" && importInfo?.status === "ready" && !!importInfo?.phone_column && importInfo?.valid_count > 0) ||
    (source === "abandoned_cart" && (cartWindow !== "custom" || !!dateFrom || !!dateTo)) ||
    ["contacts", "shopify_customer"].includes(source);

  const audienceKey = JSON.stringify([source, filter, segmentId, importId, importInfo?.phone_column]);

  // Reach and a few sample people, re-counted whenever the audience changes.
  useEffect(() => {
    if (!audienceReady) { setPreview(null); return undefined; }
    setPreviewing(true);
    const timer = setTimeout(async () => {
      try {
        const data = await api("/api/whatsapp/audiences/preview", {
          method: "POST",
          body: {
            audience_source: source,
            audience_filter: filter,
            whatsapp_audience_import_id: importId,
            whatsapp_segment_id: segmentId || null,
          },
        });
        setPreview(data);
      } catch (e) { setPreview({ error: e.message }); } finally { setPreviewing(false); }
    }, 400);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [audienceKey, audienceReady]);

  const uploadCsv = async (files) => {
    if (!files?.[0]) return;
    setUploading(true);
    setError("");
    setImportInfo(null);
    try {
      const fd = new FormData();
      fd.append("file", files[0]);
      const created = await api("/api/whatsapp/audience_imports", { method: "POST", form: fd });
      setImportId(created.id);
      const info = await waitForImport(created.id, created, 20);
      setImportInfo(info);
      if (!["ready", "failed"].includes(info?.status)) {
        setError(t("csv_slow", "Your list is still being read. Wait a minute, then upload it again."));
      }
    } catch (e) { setError(e.message); } finally { setUploading(false); }
  };

  const setPhoneColumn = async (value) => {
    try {
      const updated = await api(`/api/whatsapp/audience_imports/${importId}`, { method: "PATCH", body: { phone_column: value } });
      setImportInfo(updated);
    } catch (e) { setError(e.message); }
  };

  const reach = preview?.estimated_count;
  const reachText = previewing
    ? t("reach_counting", "Counting…")
    : preview?.error || preview?.count_error
      ? t("reach_unknown", "Counted when you send")
      : reach == null
        ? "—"
        : preview?.count_capped
          ? t("reach_capped", "More than %{count} people", { count: formatNumber(preview.count_cap || reach) })
          : t("people_count", "%{count} people", { count: formatNumber(reach) });

  const selectedSegment = segments.find((s) => String(s.id) === String(segmentId));

  const policyKey = JSON.stringify(sendPolicy);
  const knownCount = preview && !preview.error && !preview.count_error && reach != null ? reach : undefined;

  useEffect(() => {
    if (step !== 3 || !audienceReady) return undefined;
    const timer = setTimeout(async () => {
      try {
        const data = await api("/api/whatsapp/audiences/estimate", {
          method: "POST",
          body: {
            count: knownCount,
            audience_source: source,
            audience_filter: filter,
            whatsapp_segment_id: segmentId || null,
            whatsapp_audience_import_id: importId,
            whatsapp_template_id: templateId || null,
            whatsapp_account_id: accountId || null,
            send_policy: sendPolicy,
            scheduled_at: when === "later" && scheduledAt ? scheduledAt : null,
          },
        });
        setEstimate(data);
      } catch (_) { setEstimate(null); }
    }, 300);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step, audienceKey, audienceReady, knownCount, templateId, accountId, policyKey, when, scheduledAt]);

  const limits = estimate?.limits;
  const qualityLow = !!limits?.quality_low;
  const quiet = estimate?.quiet_hours;
  const cost = estimate?.cost;

  const updatePolicy = (group, changes) =>
    setSendPolicy((p) => ({ ...p, [group]: { ...p[group], ...changes } }));

  // ── Message ──────────────────────────────────────────────────────────

  const template = (templates || []).find((tpl) => String(tpl.id) === String(templateId));
  const positions = bodyPlaceholders(template);
  const needsHeader = hasHeaderVariable(template);
  const needsButton = hasDynamicButton(template);
  const fields = preview?.fields || [];
  const sample = preview?.sample?.[0];
  const sampleFields = sample?.fields || {};

  const chooseTemplate = (tplId) => {
    const tpl = (templates || []).find((x) => String(x.id) === String(tplId));
    setTemplateId(String(tplId));
    // "Hi {{1}}," is almost always the first name: fill it in so the simplest
    // message needs no setup. Any other blank starts empty for the merchant to choose.
    const first = bodyPlaceholders(tpl)[0];
    const body = componentOf(tpl, "BODY")?.text || "";
    const greeting = first && /\b(hi|hello|hey|dear|namaste|hii)[\s,]*$/i.test(body.split(`{{${first}}}`)[0]);
    setMapping(greeting ? { [first]: suggestField(fields, "greeting") } : {});
    setDefaults(greeting ? { [first]: t("default_greeting", "there") } : {});
    setHeaderField("");
    setButtonField(hasDynamicButton(tpl) ? suggestField(fields, "button") : "");
  };

  const valueFor = (key, fallback) => {
    if (key) {
      const v = String(sampleFields[key] ?? "").trim();
      if (v) return v;
      if (!sample) return `[${fieldLabel(key)}]`;
    }
    return String(fallback ?? "").trim();
  };

  const variableComplete = (p) => !!mapping[p] || !!String(defaults[p] ?? "").trim();
  const messageReady =
    !!template &&
    positions.every(variableComplete) &&
    (!needsHeader || !!headerField || !!String(defaults.header ?? "").trim()) &&
    (!needsButton || !!buttonField);

  const buttonUrl = useMemo(() => {
    const url = (componentOf(template, "BUTTONS")?.buttons || []).find((b) => (b?.type || "").toUpperCase() === "URL")?.url;
    if (!url) return undefined;
    if (!url.includes("{{")) return url;
    const slug = buttonField ? valueFor(buttonField, "") : "";
    return slug ? url.replace(/\{\{\d+\}\}/, slug) : "";
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [template, buttonField, sampleFields]);

  // ── Saving ───────────────────────────────────────────────────────────

  const body = () => ({
    name: name.trim() || defaultName(),
    audience_source: source,
    audience_filter: filter,
    whatsapp_audience_import_id: source === "csv" ? importId : null,
    whatsapp_segment_id: source === "segment" ? segmentId || null : null,
    whatsapp_account_id: accountId || null,
    whatsapp_template_id: templateId || null,
    variable_mapping: Object.fromEntries(Object.entries(mapping).filter(([, v]) => v)),
    variable_defaults: defaults,
    // Blank fallbacks already mean "skip people without it", so one policy covers both.
    missing_value_policy: "default",
    header_field: headerField || null,
    button_field: buttonField || null,
    retry_config: {
      enabled: retryEnabled,
      delays_hours: retryDelays.map(Number).filter((n) => n > 0 && n <= 168).slice(0, 5),
    },
    scheduled_at: when === "later" && scheduledAt ? scheduledAt : null,
    send_policy: sendPolicy,
  });

  const saveDraft = async () => {
    setSaving(true);
    try {
      if (draftRef.current) {
        await api(`/api/whatsapp/campaigns/${draftRef.current}`, { method: "PATCH", body: body() });
        return draftRef.current;
      }
      const created = await api("/api/whatsapp/campaigns", { method: "POST", body: body() });
      const newId = created.campaign.id;
      setDraftId(newId);
      draftRef.current = newId;
      loadedOnce.current = true;
      // Keep the address pointing at this draft so a refresh, or a trip to
      // create a message, comes back to it instead of a blank campaign.
      const params = new URLSearchParams(window.location.search);
      params.delete("audience");
      const qs = params.toString();
      window.history.replaceState({}, "", `${paths.edit(newId)}${qs ? `?${qs}` : ""}`);
      return newId;
    } finally { setSaving(false); }
  };

  const goTo = async (next) => {
    setError("");
    try {
      await saveDraft();
      setStep(next);
      setMaxStep((m) => Math.max(m, next));
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (e) { setError(e.message); }
  };

  const leaveForTemplates = async () => {
    try {
      await saveDraft();
      navigateTo("/features/whatsapp/templates");
    } catch (e) { setError(e.message); }
  };

  const saveAndExit = async () => {
    try {
      await saveDraft();
      navigateTo(paths.home());
    } catch (e) { setError(e.message); }
  };

  const sendTest = async () => {
    setTesting(true);
    setTestResults(null);
    setError("");
    try {
      const campaignId = await saveDraft();
      const data = await api(`/api/whatsapp/campaigns/${campaignId}/test`, { method: "POST", body: { phones: splitPhones(testPhones) } });
      setTestResults(data.results || []);
    } catch (e) { setError(e.message); } finally { setTesting(false); }
  };

  const launch = async () => {
    setSending(true);
    setError("");
    try {
      const campaignId = await saveDraft();
      await api(`/api/whatsapp/campaigns/${campaignId}/launch`, {
        method: "POST",
        body: {
          whatsapp_account_id: accountId || undefined,
          acknowledge_risk: acknowledgeRisk || undefined,
          ...(when === "later" ? { scheduled_at: scheduledAt } : { send_now: true }),
        },
      });
      navigateTo(paths.report(campaignId));
    } catch (e) {
      setError(e.message);
      setConfirmSend(false);
      setSending(false);
    }
  };

  // ── Render ───────────────────────────────────────────────────────────

  const account = accounts.find((a) => String(a.id) === String(accountId));
  const audienceSummary =
    source === "segment"
      ? selectedSegment?.name || t("audience_saved", "A saved audience")
      : source === "csv"
        ? t("summary_csv", "Your uploaded list")
        : audienceSourceLabel(source);

  const renderAudienceStep = () => (
    <BlockStack gap="400">
      {!id && !draftId && (
        <RecipePicker onPick={applyRecipe} busyKey={applyingRecipe} disabled={!!applyingRecipe} onError={setError} />
      )}
      <Card>
        <TextField
          label={t("campaign_name", "Campaign name")}
          value={name}
          onChange={setName}
          helpText={t("campaign_name_help", "Only you see this.")}
          autoComplete="off"
        />
      </Card>

      <Card>
        <BlockStack gap="300">
          <Text as="h2" variant="headingMd">{t("who_title", "Who should get this?")}</Text>
          <ChoiceList
            title={t("who_title", "Who should get this?")}
            titleHidden
            choices={[
              ...audienceChoices(),
              ...(source === "shopify_customer" ? [{ value: "shopify_customer", label: audienceSourceLabel("shopify_customer") }] : []),
            ].map((choice) => ({
              ...choice,
              renderChildren: (selected) => selected && renderAudienceDetail(choice.value),
            }))}
            selected={[source]}
            onChange={(v) => setSource(v[0])}
          />
        </BlockStack>
      </Card>

      {source === "contacts" && contactsTotal === 0 && (
        <Banner
          tone="warning"
          title={t("no_contacts_title", "You don't have any contacts yet")}
          action={{ content: t("go_to_audiences", "Import customers"), onAction: () => navigateTo(paths.home("audiences")) }}
        >
          {t("no_contacts_body", "Import your Shopify customers first, or pick another audience. Your campaign is kept as a draft.")}
        </Banner>
      )}
    </BlockStack>
  );

  const renderAudienceDetail = (value) => {
    if (value === "abandoned_cart") {
      return (
        <Box paddingBlockStart="200" paddingInlineStart="600">
          <BlockStack gap="200">
            <Box maxWidth="260px">
              <Select label={t("cart_window", "Left checkout")} options={CART_WINDOWS()} value={cartWindow} onChange={setCartWindow} />
            </Box>
            {cartWindow === "custom" && (
              <InlineGrid columns={{ xs: 1, sm: 2 }} gap="200">
                <TextField label={t("from", "From")} type="date" value={dateFrom} onChange={setDateFrom} autoComplete="off" />
                <TextField label={t("to", "To")} type="date" value={dateTo} onChange={setDateTo} autoComplete="off" />
              </InlineGrid>
            )}
          </BlockStack>
        </Box>
      );
    }
    if (value === "segment") {
      return (
        <Box paddingBlockStart="200" paddingInlineStart="600">
          <BlockStack gap="200">
            {segments.length > 0 ? (
              <Select
                label={t("pick_audience", "Audience")}
                options={[
                  { label: t("choose", "Choose…"), value: "" },
                  ...segments.map((s) => ({
                    label: `${s.name} (${t("people_count", "%{count} people", { count: formatNumber(s.count ?? 0) })})`,
                    value: String(s.id),
                  })),
                ]}
                value={String(segmentId)}
                onChange={setSegmentId}
                helpText={selectedSegment ? describeFilters(selectedSegment.filters) : undefined}
              />
            ) : (
              <Text as="p" variant="bodySm" tone="subdued">{t("no_audiences", "You haven't saved any audiences yet.")}</Text>
            )}
            <Box>
              <Button variant="plain" onClick={() => setCreatingAudience(true)}>{t("create_audience_here", "Create a new audience")}</Button>
            </Box>
          </BlockStack>
        </Box>
      );
    }
    if (value === "csv") {
      return (
        <Box paddingBlockStart="200" paddingInlineStart="600">
          <BlockStack gap="300">
            <DropZone accept=".csv,text/csv" type="file" onDrop={uploadCsv} allowMultiple={false} disabled={uploading}>
              {uploading ? (
                <Box padding="600">
                  <InlineStack gap="200" align="center" blockAlign="center">
                    <Spinner size="small" />
                    <Text as="span">{t("importing", "Reading your list…")}</Text>
                  </InlineStack>
                </Box>
              ) : (
                <DropZone.FileUpload
                  actionTitle={importInfo ? t("replace_file", "Upload a different file") : t("choose_file", "Choose CSV file")}
                  actionHint={t("csv_hint", "Needs a column with phone numbers, including the country code")}
                />
              )}
            </DropZone>
            {importInfo?.status === "failed" && (
              <Banner tone="critical">{t("import_failed", "We couldn't read this file: %{error}", { error: importInfo.error })}</Banner>
            )}
            {importInfo?.status === "ready" && (
              <BlockStack gap="200">
                <Select
                  label={t("phone_column", "Which column has the phone numbers?")}
                  options={[{ label: t("choose", "Choose…"), value: "" }, ...(importInfo.columns || []).map((col) => ({ label: col, value: col }))]}
                  value={importInfo.phone_column || ""}
                  onChange={setPhoneColumn}
                  error={importInfo.phone_column && importInfo.valid_count === 0 ? t("phone_column_empty", "No valid phone numbers in this column.") : undefined}
                />
                {importInfo.phone_column && importInfo.valid_count > 0 && (
                  <Text as="p" variant="bodySm" tone="subdued">
                    {t("csv_valid", "%{valid} of %{rows} rows have a valid number.", {
                      valid: formatNumber(importInfo.valid_count),
                      rows: formatNumber(importInfo.row_count),
                    })}
                  </Text>
                )}
              </BlockStack>
            )}
          </BlockStack>
        </Box>
      );
    }
    return null;
  };

  const renderFieldRow = ({ label, help, fieldValue, onField, fallbackValue, onFallback, allowFixed = true, required }) => (
    <BlockStack gap="200">
      <InlineGrid columns={{ xs: 1, sm: 2 }} gap="300">
        <Select
          label={label}
          helpText={help}
          options={[
            ...(allowFixed ? [{ label: t("same_for_everyone", "Same text for everyone"), value: "" }] : [{ label: t("choose", "Choose…"), value: "" }]),
            ...fieldOptions(fields),
          ]}
          value={fieldValue || ""}
          onChange={onField}
          error={required && !fieldValue ? t("choose_link", "Choose what this links to") : undefined}
        />
        {onFallback && (
          <TextField
            label={fieldValue ? t("fallback", "If someone doesn't have it, use") : t("fixed_text", "Text")}
            value={fallbackValue || ""}
            onChange={onFallback}
            placeholder={fieldValue ? t("fallback_placeholder", "Leave empty to skip them") : ""}
            autoComplete="off"
          />
        )}
      </InlineGrid>
    </BlockStack>
  );

  const recipeWaiting = !!recipe && !templateId && !recipe.approved_template_id;
  const recipeBody = (recipe?.template_payload?.components || []).find((c) => c.type === "BODY")?.text;

  const renderRecipeTemplate = () =>
    recipe.template_status === "pending" ? (
      <Banner tone="info" title={t("template_waiting_title", "Waiting for WhatsApp to approve your message")}>
        {t("template_waiting_body", "This usually takes a few hours. Your campaign is saved as a draft. Come back to this page to send it once the message is approved.")}
      </Banner>
    ) : (
      <Banner
        tone="info"
        title={t("template_waiting_submit_title", "Submit this message for approval")}
        action={{
          content: t("template_waiting_submit", "Submit for approval"),
          onAction: submitRecipeTemplate,
          loading: submittingTemplate,
        }}
      >
        <BlockStack gap="200">
          <Text as="p">
            {recipe.template_status
              ? t("template_waiting_resubmit", "WhatsApp didn't approve the last version of this message. You can submit it again.")
              : t("template_waiting_submit_body", "WhatsApp needs to approve this message before you can send it. Your campaign stays a draft until then.")}
          </Text>
          {recipeBody && (
            <Box background="bg-surface" padding="300" borderRadius="200">
              <Text as="p" variant="bodySm">{recipeBody}</Text>
            </Box>
          )}
        </BlockStack>
      </Banner>
    );

  const renderMessageStep = () => (
    <BlockStack gap="400">
      {recipeWaiting && renderRecipeTemplate()}
      {accounts.length > 1 && (
        <Card>
          <Select
            label={t("send_from", "Send from")}
            options={accounts.map((a) => ({
              label: `${a.display_label || a.verified_name || a.display_phone_number}${a.display_phone_number && a.display_label ? ` · ${a.display_phone_number}` : ""}${a.is_default ? ` (${t("default", "default")})` : ""}`,
              value: String(a.id),
            }))}
            value={accountId}
            onChange={(v) => { setAccountId(v); setTemplateId(""); setMapping({}); setDefaults({}); setHeaderField(""); setButtonField(""); }}
            helpText={t("send_from_help", "Each number has its own approved messages.")}
          />
        </Card>
      )}

      <Card>
        <BlockStack gap="300">
          <InlineStack align="space-between" blockAlign="center" gap="200">
            <BlockStack gap="050">
              <Text as="h2" variant="headingMd">{t("choose_message", "Choose a message")}</Text>
              <Text as="p" variant="bodySm" tone="subdued">
                {t("choose_message_help", "WhatsApp only allows messages it has approved. You can personalise them below.")}
              </Text>
            </BlockStack>
            <Button onClick={leaveForTemplates} loading={saving}>{t("new_message", "New message")}</Button>
          </InlineStack>
          {templates === null ? (
            <SkeletonBodyText lines={4} />
          ) : templates.length === 0 ? (
            <Banner tone="info" title={t("no_templates_title", "No approved messages yet")}>
              {t("no_templates_body", "Pick a ready-made message or write your own and send it to WhatsApp for approval, usually a few minutes to a few hours. Your campaign is saved as a draft, so you can come back to it.")}
            </Banner>
          ) : (
            <div role="radiogroup" aria-label={t("choose_message", "Choose a message")}>
              <InlineGrid columns={{ xs: 1, md: 2 }} gap="300">
                {templates.map((tpl) => (
                  <TemplateOption
                    key={tpl.id}
                    template={tpl}
                    selected={String(tpl.id) === String(templateId)}
                    onSelect={() => chooseTemplate(tpl.id)}
                  />
                ))}
              </InlineGrid>
            </div>
          )}
        </BlockStack>
      </Card>

      {template && (positions.length > 0 || needsHeader || needsButton) && (
        <Card>
          <BlockStack gap="400">
            <BlockStack gap="050">
              <Text as="h2" variant="headingMd">{t("personalise", "Personalise")}</Text>
              <Text as="p" variant="bodySm" tone="subdued">
                {t("personalise_help", "Fill each blank with a detail about the customer, or with the same text for everyone. The preview shows the result.")}
              </Text>
            </BlockStack>
            {needsHeader &&
              renderFieldRow({
                label: t("blank_title", "Title"),
                help: componentOf(template, "HEADER")?.text,
                fieldValue: headerField,
                onField: setHeaderField,
                fallbackValue: defaults.header,
                onFallback: (v) => setDefaults((d) => ({ ...d, header: v })),
              })}
            {positions.map((p) => (
              <React.Fragment key={p}>
                {renderFieldRow({
                  label: t("blank_n", "Blank %{n}", { n: p }),
                  help: placeholderContext(template, p),
                  fieldValue: mapping[p],
                  onField: (v) => setMapping((m) => ({ ...m, [p]: v })),
                  fallbackValue: defaults[p],
                  onFallback: (v) => setDefaults((d) => ({ ...d, [p]: v })),
                })}
              </React.Fragment>
            ))}
            {needsButton &&
              renderFieldRow({
                label: t("button_link", "Button link"),
                help: (componentOf(template, "BUTTONS")?.buttons || []).find((b) => (b?.url || "").includes("{{"))?.url,
                fieldValue: buttonField,
                onField: setButtonField,
                allowFixed: false,
                required: true,
              })}
          </BlockStack>
        </Card>
      )}
    </BlockStack>
  );

  const renderReviewStep = () => (
    <BlockStack gap="400">
      {qualityLow && (
        <Banner tone="critical" title={t("quality_low_title", "Your number quality is low")}>
          <BlockStack gap="200">
            <Text as="p">{t("quality_low_body", "Sending now could get your number restricted. Wait until the quality improves, or send to a smaller, more engaged audience.")}</Text>
            <Checkbox
              label={t("quality_low_ack", "I understand the risk")}
              checked={acknowledgeRisk}
              onChange={setAcknowledgeRisk}
            />
          </BlockStack>
        </Banner>
      )}
      {!qualityLow && limits?.quality_warning && (
        <Banner tone="warning">
          {t("quality_medium", "Your number quality is medium. Keep messages relevant to avoid restrictions.")}
        </Banner>
      )}
      {limits?.daily_limit && (limits.exceeds_daily_limit || limits.near_daily_limit) && (
        <Banner tone="warning">
          {limits.exceeds_daily_limit
            ? t("limit_exceeds", "This audience is bigger than your daily messaging limit of %{limit} customers. WhatsApp may hold back messages past the limit until the next day.", { limit: formatNumber(limits.daily_limit) })
            : t("limit_near", "This audience is close to your daily messaging limit of %{limit} customers. Your order updates count toward the same limit.", { limit: formatNumber(limits.daily_limit) })}
        </Banner>
      )}
      <Card>
        <BlockStack gap="300">
          <Text as="h2" variant="headingMd">{t("review_title", "Check your campaign")}</Text>
          {[
            [t("review_to", "To"), `${audienceSummary} · ${reachText}`, 1],
            [t("review_message", "Message"), template ? humanizeTemplate(template.name) : "—", 2],
            ...(account ? [[t("review_from", "From"), [account.verified_name, account.display_phone_number].filter(Boolean).join(" · "), 2]] : []),
          ].map(([label, value, target], i) => (
            <React.Fragment key={label}>
              {i > 0 && <Divider />}
              <InlineStack align="space-between" blockAlign="center" gap="300" wrap={false}>
                <BlockStack gap="050">
                  <Text as="span" variant="bodySm" tone="subdued">{label}</Text>
                  <Text as="span">{value}</Text>
                </BlockStack>
                <Button variant="plain" onClick={() => setStep(target)}>{t("change", "Change")}</Button>
              </InlineStack>
            </React.Fragment>
          ))}
          {cost && cost.count > 0 && (
            <>
              <Divider />
              <BlockStack gap="050">
                <Text as="span" variant="bodySm" tone="subdued">{t("cost_label", "Estimated WhatsApp charges")}</Text>
                <Text as="span">
                  {t("cost_line", "About %{amount} (%{count} messages × %{rate}), plus 18% GST, billed by Meta to your WhatsApp account.", {
                    amount: formatMoney(cost.amount, cost.currency),
                    count: formatNumber(cost.count),
                    rate: formatMoney(cost.rate, cost.currency, 2),
                  })}
                </Text>
                {estimate.has_non_indian_numbers && (
                  <Text as="span" variant="bodySm" tone="subdued">{t("cost_india_rates", "This estimate uses India rates.")}</Text>
                )}
              </BlockStack>
            </>
          )}
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="300">
          <ChoiceList
            title={t("when_title", "When should it go out?")}
            choices={[
              { label: t("when_now", "Right away"), value: "now" },
              { label: t("when_later", "At a later time"), value: "later" },
            ]}
            selected={[when]}
            onChange={(v) => setWhen(v[0])}
          />
          {when === "later" && (
            <Box maxWidth="320px">
              <TextField
                label={t("send_at", "Date and time")}
                type="datetime-local"
                value={scheduledAt}
                onChange={setScheduledAt}
                min={scheduleTz?.now}
                helpText={scheduleHelpText(scheduleTz)}
                autoComplete="off"
              />
            </Box>
          )}
          {sendPolicy.quiet_hours.enabled && quiet?.in_quiet_hours_at_send && quiet.next_window_display && (
            <Banner tone="info">
              {when === "later"
                ? t("quiet_scheduled", "The time you picked is inside quiet hours. Sending will start at %{time} (store time).", { time: quiet.next_window_display })
                : t("quiet_now", "It's quiet hours for your store right now. Sending will start at %{time} (store time).", { time: quiet.next_window_display })}
            </Banner>
          )}
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="300">
          <BlockStack gap="050">
            <Text as="h2" variant="headingMd">{t("test_title", "Send yourself a test")}</Text>
            <Text as="p" variant="bodySm" tone="subdued">
              {t("test_help", "See the real message on your phone before anyone else does. Uses the details of the first person in your audience.")}
            </Text>
          </BlockStack>
          <InlineStack gap="200" blockAlign="end" wrap>
            <Box minWidth="260px">
              <TextField
                label={t("test_phone", "Your WhatsApp number")}
                value={testPhones}
                onChange={setTestPhones}
                placeholder="919999988888"
                helpText={t("test_phone_help", "With country code. Separate several with commas.")}
                autoComplete="off"
              />
            </Box>
            <Button onClick={sendTest} loading={testing} disabled={!splitPhones(testPhones).length}>{t("send_test", "Send test")}</Button>
          </InlineStack>
          {testResults && testResults.map((r) => (
            <Banner
              key={r.phone}
              tone={r.status === "failed" ? "critical" : r.status === "skipped" ? "warning" : "success"}
            >
              {r.status === "failed" || r.status === "skipped"
                ? t("test_failed", "%{phone}: %{error}", { phone: r.phone, error: r.error || r.status })
                : t("test_sent", "Test sent to %{phone}. Check WhatsApp on that phone.", { phone: r.phone })}
            </Banner>
          ))}
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="300">
          <Text as="h2" variant="headingMd">{t("advanced", "Delivery settings")}</Text>
          <Checkbox
            label={t("quiet_label", "Don't send between %{start} and %{end} (store time)", {
              start: hourLabel(sendPolicy.quiet_hours.start_hour),
              end: hourLabel(sendPolicy.quiet_hours.end_hour),
            })}
            helpText={t("quiet_help", "Messages due during these hours wait and go out when they end.")}
            checked={!!sendPolicy.quiet_hours.enabled}
            onChange={(v) => updatePolicy("quiet_hours", { enabled: v })}
          />
          {sendPolicy.quiet_hours.enabled && (
            <Box paddingInlineStart="600" maxWidth="420px">
              <InlineGrid columns={2} gap="200">
                <Select
                  label={t("quiet_start", "Stop sending at")}
                  options={HOUR_OPTIONS()}
                  value={String(sendPolicy.quiet_hours.start_hour)}
                  onChange={(v) => updatePolicy("quiet_hours", { start_hour: Number(v) })}
                />
                <Select
                  label={t("quiet_end", "Start again at")}
                  options={HOUR_OPTIONS()}
                  value={String(sendPolicy.quiet_hours.end_hour)}
                  onChange={(v) => updatePolicy("quiet_hours", { end_hour: Number(v) })}
                />
              </InlineGrid>
            </Box>
          )}
          <Checkbox
            label={t("fcap_label", "Send at most 1 campaign message per customer every %{hours} hours", { hours: sendPolicy.frequency_cap.hours })}
            helpText={t("fcap_help", "Customers who got a message from another campaign in the last %{hours} hours are skipped. Order updates don't count.", { hours: sendPolicy.frequency_cap.hours })}
            checked={!!sendPolicy.frequency_cap.enabled}
            onChange={(v) => updatePolicy("frequency_cap", { enabled: v })}
          />
          <Divider />
          <InlineStack align="space-between" blockAlign="center">
            <Text as="h3" variant="headingSm">{t("retry_title", "Retries")}</Text>
            <Button variant="plain" disclosure={showAdvanced ? "up" : "down"} onClick={() => setShowAdvanced((v) => !v)}>
              {showAdvanced ? t("hide", "Hide") : t("show", "Show")}
            </Button>
          </InlineStack>
          <Collapsible open={showAdvanced} id="campaign-advanced">
            <BlockStack gap="300">
              <Checkbox
                label={t("retry_label", "Try again if WhatsApp holds a message back")}
                helpText={t("retry_help", "WhatsApp sometimes limits how many promotions one person gets per day. Retrying later often gets through. Numbers that aren't on WhatsApp are never retried.")}
                checked={retryEnabled}
                onChange={setRetryEnabled}
              />
              {retryEnabled && (
                <BlockStack gap="200">
                  {retryDelays.map((d, i) => (
                    <InlineStack key={i} gap="200" blockAlign="end" wrap={false}>
                      <Box maxWidth="220px">
                        <TextField
                          label={i === 0 ? t("retry_first", "First retry after") : t("retry_next", "Retry %{n} after", { n: i + 1 })}
                          type="number"
                          min={1}
                          max={168}
                          suffix={t("hours", "hours")}
                          value={d}
                          onChange={(v) => setRetryDelays((arr) => arr.map((x, j) => (j === i ? v : x)))}
                          autoComplete="off"
                        />
                      </Box>
                      {retryDelays.length > 1 && (
                        <Button variant="plain" onClick={() => setRetryDelays((arr) => arr.filter((_, j) => j !== i))}>
                          {t("remove", "Remove")}
                        </Button>
                      )}
                    </InlineStack>
                  ))}
                  {retryDelays.length < 5 && (
                    <Box>
                      <Button variant="plain" onClick={() => setRetryDelays((arr) => [...arr, "24"])}>{t("retry_add", "Add another retry")}</Button>
                    </Box>
                  )}
                </BlockStack>
              )}
            </BlockStack>
          </Collapsible>
        </BlockStack>
      </Card>
    </BlockStack>
  );

  const canContinue = step === 1 ? audienceReady && !!name.trim() : step === 2 ? messageReady : false;
  // With no ready number in the list the server falls back to the store's
  // default and explains any problem, so only block on a mismatch we can see.
  const canSend =
    audienceReady && messageReady && (when === "now" || !!scheduledAt) && (accounts.length === 0 || !!account) &&
    (!qualityLow || acknowledgeRisk);

  const footer = (
    <InlineStack align="space-between" blockAlign="center">
      <Box>
        {step > 1 && <Button onClick={() => setStep(step - 1)}>{t("back", "Back")}</Button>}
      </Box>
      {step < 3 ? (
        <Button variant="primary" onClick={() => goTo(step + 1)} disabled={!canContinue} loading={saving}>
          {t("continue", "Continue")}
        </Button>
      ) : (
        <Button variant="primary" onClick={() => setConfirmSend(true)} disabled={!canSend}>
          {when === "later" ? t("schedule_campaign", "Schedule campaign") : t("send_campaign", "Send campaign")}
        </Button>
      )}
    </InlineStack>
  );

  const sidebar = (
    <div style={{ position: "sticky", top: 16 }}>
      <BlockStack gap="400">
        <Card>
          <BlockStack gap="300">
            <Text as="h2" variant="headingSm">{t("preview_title", "Preview")}</Text>
            <MessagePreview
              template={template}
              resolve={(p) => valueFor(mapping[p], defaults[p])}
              resolveHeader={() => valueFor(headerField, defaults.header)}
              buttonUrl={buttonUrl}
              recipientName={sample?.name || sample?.phone}
            />
          </BlockStack>
        </Card>
        <Card>
          <BlockStack gap="200">
            <Text as="h2" variant="headingSm">{t("reach_title", "Who gets it")}</Text>
            <InlineStack gap="200" blockAlign="center">
              {previewing && <Spinner size="small" />}
              <Text as="p" variant="headingLg">{audienceReady ? reachText : "—"}</Text>
            </InlineStack>
            <Text as="p" variant="bodySm" tone="subdued">{audienceSummary}</Text>
            {(preview?.sample || []).length > 0 && (
              <Text as="p" variant="bodySm" tone="subdued">
                {t("reach_including", "Including %{names}", {
                  names: preview.sample.map((r) => r.name || r.phone).filter(Boolean).slice(0, 3).join(", "),
                })}
              </Text>
            )}
            <Text as="p" variant="bodySm" tone="subdued">
              {t("reach_note", "People who opted out are left out automatically.")}
            </Text>
          </BlockStack>
        </Card>
      </BlockStack>
    </div>
  );

  return (
    <WhatsappLayout
      title={id || draftId ? name || t("edit_campaign", "Edit campaign") : t("new_campaign", "New campaign")}
      backLabel={t("back_to_campaigns", "Campaigns")}
      onBack={() => navigateTo(paths.home())}
      secondaryActions={[{ content: t("save_draft", "Save draft and exit"), onAction: saveAndExit, loading: saving }]}
    >
      {!loaded ? (
        <Card><SkeletonBodyText lines={10} /></Card>
      ) : (
        <BlockStack gap="400">
          <StepNav step={step} maxStep={maxStep} onSelect={setStep} />
          {error && <Banner tone="critical" onDismiss={() => setError("")}>{error}</Banner>}
          {notice && <Banner tone="success" onDismiss={() => setNotice("")}>{notice}</Banner>}
          <Layout>
            <Layout.Section>
              <BlockStack gap="400">
                {step === 1 && renderAudienceStep()}
                {step === 2 && renderMessageStep()}
                {step === 3 && renderReviewStep()}
                {footer}
              </BlockStack>
            </Layout.Section>
            <Layout.Section variant="oneThird">{sidebar}</Layout.Section>
          </Layout>
        </BlockStack>
      )}

      {creatingAudience && (
        <AudienceEditor
          onClose={() => setCreatingAudience(false)}
          onSaved={async (segment) => {
            setCreatingAudience(false);
            await loadSegments();
            if (segment?.id) setSegmentId(String(segment.id));
            setNotice(t("audience_created", "Audience saved and selected."));
          }}
          onError={setError}
        />
      )}

      {confirmSend && (
        <Modal
          open
          onClose={() => setConfirmSend(false)}
          title={when === "later" ? t("confirm_schedule_title", "Schedule this campaign?") : t("confirm_send_title", "Send this campaign now?")}
          primaryAction={{
            content: when === "later" ? t("schedule_campaign", "Schedule campaign") : t("send_campaign", "Send campaign"),
            onAction: launch,
            loading: sending,
          }}
          secondaryActions={[{ content: t("back", "Back"), onAction: () => setConfirmSend(false) }]}
        >
          <Modal.Section>
            <BlockStack gap="200">
              <Text as="p">
                {when === "later"
                  ? t("confirm_schedule_body", "\"%{name}\" goes to %{reach} (%{audience}) at %{time}.", {
                      name: name.trim(), reach: reachText, audience: audienceSummary, time: scheduledAt.replace("T", " "),
                    })
                  : t("confirm_send_body", "\"%{name}\" goes to %{reach} (%{audience}) right away.", {
                      name: name.trim(), reach: reachText, audience: audienceSummary,
                    })}
              </Text>
              <Text as="p" variant="bodySm" tone="subdued">
                {t("confirm_billing", "WhatsApp charges for each message delivered. You can pause or stop the campaign while it sends.")}
              </Text>
            </BlockStack>
          </Modal.Section>
        </Modal>
      )}
    </WhatsappLayout>
  );
};

export default CampaignBuilder;
