import I18n from "../../../i18n-lang";

// Every string on the campaigns pages lives under `whatsapp_campaigns.*` in
// config/localeJson/en.json; the fallback here keeps the page readable if a key
// is missing from a locale.
export const t = (key, fallback, opts = {}) =>
  I18n.t(`whatsapp_campaigns.${key}`, { defaultValue: fallback, ...opts });

export const BASE_PATH = "/features/whatsapp-campaigns";
// Where the sidebar item used to point before campaigns had their own page.
// Still routed here so old links (Sidekick, bookmarks) land somewhere real.
export const LEGACY_PATHS = ["/features/whatsapp/campaigns", "/features/whatsapp/audience"];

export const paths = {
  home: (tab) => (tab === "audiences" ? `${BASE_PATH}?tab=audiences` : BASE_PATH),
  newCampaign: () => `${BASE_PATH}/new`,
  edit: (id) => `${BASE_PATH}/${id}/edit`,
  report: (id) => `${BASE_PATH}/${id}`,
  recipe: (key) => `${BASE_PATH}/new?recipe=${encodeURIComponent(key)}`,
};

export const statusLabel = (status) =>
  ({
    draft: t("status_draft", "Draft"),
    scheduled: t("status_scheduled", "Scheduled"),
    building: t("status_building", "Preparing"),
    testing: t("status_testing", "Testing"),
    sending: t("status_sending", "Sending"),
    paused: t("status_paused", "Paused"),
    retry_waiting: t("status_retry_waiting", "Retrying soon"),
    completed: t("status_completed", "Sent"),
    cancelled: t("status_cancelled", "Cancelled"),
    failed: t("status_failed", "Failed"),
  })[status] || status;

export const STATUS_TONE = {
  scheduled: "info",
  building: "info",
  sending: "attention",
  paused: "warning",
  retry_waiting: "warning",
  completed: "success",
  failed: "critical",
};

export const STATUS_PROGRESS = {
  draft: "incomplete",
  scheduled: "incomplete",
  building: "partiallyComplete",
  sending: "partiallyComplete",
  paused: "partiallyComplete",
  retry_waiting: "partiallyComplete",
  completed: "complete",
};

// Recipient counts are kept per current status: a read message has left
// delivered_count, a delivered one has left sent_count. Totals add them back.
export const campaignTotals = (c) => {
  const delivered = (c.delivered_count || 0) + (c.read_count || 0);
  return { sent: (c.sent_count || 0) + delivered, delivered, read: c.read_count || 0 };
};

export const percent = (part, whole) => (whole > 0 ? Math.round((part * 100) / whole) : 0);

export const formatNumber = (n) => Number(n || 0).toLocaleString();

// Template variables are filled from keys like `contact.first_name`. Merchants
// pick from these by name, never by key.
const fieldLabels = () => ({
  "cart.name": t("field_customer_name", "Customer name"),
  "cart.recovery_url": t("field_checkout_link", "Checkout link (to finish the order)"),
  "cart.total": t("field_cart_total", "Cart total"),
  "cart.phone": t("field_phone", "Phone number"),
  "cart.country": t("field_country", "Country"),
  "customer.first_name": t("field_first_name", "First name"),
  "customer.last_name": t("field_last_name", "Last name"),
  "customer.email": t("field_email", "Email"),
  "customer.tags": t("field_tags", "Tags"),
  "customer.order_count": t("field_order_count", "Number of orders"),
  "contact.name": t("field_full_name", "Full name"),
  "contact.first_name": t("field_first_name", "First name"),
  "contact.last_name": t("field_last_name", "Last name"),
  "contact.email": t("field_email", "Email"),
  "contact.phone": t("field_phone", "Phone number"),
  "contact.tags": t("field_tags", "Tags"),
  "contact.order_count": t("field_order_count", "Number of orders"),
  "contact.total_spent": t("field_total_spent", "Total spent"),
});

export const fieldLabel = (key) => {
  if (!key) return "";
  const known = fieldLabels()[key];
  if (known) return known;
  if (key.startsWith("contact.attr.")) {
    return t("field_custom", "%{name} (custom field)", { name: key.slice(13).replace(/_/g, " ") });
  }
  if (key.startsWith("csv.")) {
    return t("field_csv", "%{name} (from your CSV)", { name: key.slice(4) });
  }
  return key;
};

export const fieldOptions = (fields) =>
  fields.map((f) => ({ label: fieldLabel(f), value: f }));

// Best first guess for a variable so a one-variable greeting template works
// without any mapping. The merchant still sees it in the preview and can change it.
export const suggestField = (fields, kind) => {
  const pick = (...candidates) => candidates.find((c) => fields.includes(c)) || "";
  if (kind === "button") return pick("cart.recovery_url");
  if (kind === "greeting") {
    return (
      pick("contact.first_name", "customer.first_name", "cart.name") ||
      fields.find((f) => /^csv\..*first.?name/i.test(f)) ||
      fields.find((f) => /^csv\..*name/i.test(f)) ||
      ""
    );
  }
  return "";
};

// Who a campaign can go to. Contacts come from the store automatically, so
// the merchant chooses a group rather than a data source.
export const audienceChoices = () => [
  {
    value: "contacts",
    label: t("audience_everyone", "Everyone subscribed"),
    helpText: t(
      "audience_everyone_help",
      "All customers and shoppers who left a checkout, except anyone who opted out."
    ),
  },
  {
    value: "abandoned_cart",
    label: t("audience_abandoned", "Shoppers who didn't finish checkout"),
    helpText: t("audience_abandoned_help", "Bring back people who left a checkout with items in it."),
  },
  {
    value: "segment",
    label: t("audience_saved", "A saved audience"),
    helpText: t("audience_saved_help", "Repeat buyers, lapsed customers, a tag, or any group you have saved."),
  },
  {
    value: "csv",
    label: t("audience_csv", "Upload a list (CSV)"),
    helpText: t("audience_csv_help", "Send to a one-off list of phone numbers. It is not added to your contacts."),
  },
];

export const audienceSourceLabel = (source) => {
  if (source === "shopify_customer") return t("audience_customers", "Shopify customers");
  return audienceChoices().find((c) => c.value === source)?.label || source;
};

// Ready-made audiences a merchant can add with one click.
export const audiencePresets = () => [
  {
    key: "repeat",
    name: t("preset_repeat_name", "Repeat buyers"),
    description: t("preset_repeat_description", "Ordered 2 or more times"),
    filters: { min_orders: "2" },
  },
  {
    key: "recent",
    name: t("preset_recent_name", "Recent buyers"),
    description: t("preset_recent_description", "Ordered in the last 30 days"),
    filters: { last_order_within_days: "30" },
  },
  {
    key: "lapsed",
    name: t("preset_lapsed_name", "Haven't ordered in 60 days"),
    description: t("preset_lapsed_description", "Bought before, but not in the last 60 days"),
    filters: { last_order_older_than_days: "60" },
  },
  {
    key: "never",
    name: t("preset_never_name", "Never ordered"),
    description: t("preset_never_description", "Subscribed, but no order yet"),
    filters: { max_orders: "0" },
  },
  {
    key: "cod_never_paid",
    name: t("preset_cod_only_name", "COD buyers who never paid online"),
    description: t("preset_cod_only_description", "Only ever paid cash on delivery"),
    filters: { cod_only: true },
  },
  {
    key: "rto",
    name: t("preset_rto_name", "Customers with returns or RTO"),
    description: t("preset_rto_description", "Had at least one return or RTO. Based on orders synced to COD King"),
    filters: { rto: "only" },
  },
  {
    key: "unconfirmed_cod",
    name: t("preset_unconfirmed_name", "COD orders not confirmed in the last 7 days"),
    description: t("preset_unconfirmed_description", "Placed a COD order in the last 7 days that isn't confirmed yet"),
    filters: { unconfirmed_cod_within_days: "7" },
  },
];

const list = (items) => items.map((x) => `"${x}"`).join(", ");

// A saved audience's rules as one plain sentence, so a merchant can tell what
// it means without opening the editor.
export const describeFilters = (filters = {}) => {
  const f = filters || {};
  const parts = [];
  const has = (k) => f[k] !== undefined && f[k] !== null && String(f[k]).trim() !== "";
  if (has("min_orders") && has("max_orders") && String(f.min_orders) === String(f.max_orders)) {
    parts.push(t("rule_orders_exact", "placed exactly %{n} orders", { n: f.min_orders }));
  } else {
    if (has("min_orders")) parts.push(t("rule_min_orders", "placed at least %{n} orders", { n: f.min_orders }));
    if (has("max_orders")) {
      parts.push(
        String(f.max_orders) === "0"
          ? t("rule_no_orders", "have not ordered yet")
          : t("rule_max_orders", "placed at most %{n} orders", { n: f.max_orders })
      );
    }
  }
  if (has("min_spent")) parts.push(t("rule_min_spent", "spent at least %{n}", { n: f.min_spent }));
  if (has("max_spent")) parts.push(t("rule_max_spent", "spent at most %{n}", { n: f.max_spent }));
  if (has("last_order_within_days")) {
    parts.push(t("rule_recent", "ordered in the last %{n} days", { n: f.last_order_within_days }));
  }
  if (has("last_order_older_than_days")) {
    parts.push(t("rule_lapsed", "haven't ordered in %{n} days", { n: f.last_order_older_than_days }));
  }
  if (f.cod_only === true || f.cod_only === "true") parts.push(t("rule_cod_only", "only ever paid cash on delivery"));
  if (has("min_cod_orders")) parts.push(t("rule_min_cod_orders", "placed at least %{n} COD orders", { n: f.min_cod_orders }));
  if (f.rto === "only") parts.push(t("rule_rto_only", "had a return or RTO"));
  if (f.rto === "exclude") parts.push(t("rule_rto_exclude", "never had a return or RTO"));
  if (has("unconfirmed_cod_within_days")) {
    parts.push(t("rule_unconfirmed_cod", "have a COD order from the last %{n} days that isn't confirmed", { n: f.unconfirmed_cod_within_days }));
  }
  if ((f.tags_any || []).length) parts.push(t("rule_tags_any", "are tagged %{tags}", { tags: list(f.tags_any) }));
  if ((f.tags_all || []).length) parts.push(t("rule_tags_all", "have every tag %{tags}", { tags: list(f.tags_all) }));
  if ((f.tags_none || []).length) parts.push(t("rule_tags_none", "are not tagged %{tags}", { tags: list(f.tags_none) }));
  if (has("created_from")) parts.push(t("rule_added_after", "were added on or after %{d}", { d: f.created_from }));
  if (has("created_to")) parts.push(t("rule_added_before", "were added on or before %{d}", { d: f.created_to }));

  if (!parts.length) return t("rule_everyone", "Everyone subscribed");
  const joined =
    parts.length === 1 ? parts[0] : `${parts.slice(0, -1).join(", ")} ${t("rule_and", "and")} ${parts[parts.length - 1]}`;
  return t("rule_sentence", "Subscribed contacts who %{rules}", { rules: joined });
};

// Accepts "919999988888", "+91 99999 88888", or several separated by commas.
export const splitPhones = (raw) =>
  String(raw || "")
    .split(/[,\n]/)
    .map((p) => p.replace(/[^\d]/g, ""))
    .filter(Boolean);

export const parseTags = (raw) =>
  String(raw || "")
    .split(",")
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean);
