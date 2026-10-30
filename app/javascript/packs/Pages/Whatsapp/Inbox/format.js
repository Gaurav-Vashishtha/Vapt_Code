import I18n from "../../../i18n-lang";

export const INBOX_BASE = "/features/whatsapp/inbox";
export const INBOX_SETTINGS_PATH = `${INBOX_BASE}/settings`;
export const conversationPath = (id) => `${INBOX_BASE}/${id}`;
export const UNREAD_EVENT = "inbox:unread";

export const t = (key, defaultValue, opts = {}) =>
  I18n.t(`whatsapp_inbox.${key}`, { defaultValue, ...opts });

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

const toDate = (iso) => {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : d;
};

const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

export const relativeTime = (iso, now = Date.now()) => {
  const d = toDate(iso);
  if (!d) return "";
  const diff = now - d.getTime();
  if (diff < MINUTE) return t("time.just_now", "Just now");
  if (diff < HOUR) return t("time.minutes_short", "%{count}m", { count: Math.floor(diff / MINUTE) });
  if (startOfDay(d) === startOfDay(new Date(now))) {
    return t("time.hours_short", "%{count}h", { count: Math.floor(diff / HOUR) });
  }
  if (startOfDay(d) === startOfDay(new Date(now - DAY))) return t("thread.yesterday", "Yesterday");
  const sameYear = d.getFullYear() === new Date(now).getFullYear();
  return d.toLocaleDateString(undefined, sameYear ? { day: "numeric", month: "short" } : { dateStyle: "medium" });
};

export const timeOfDay = (iso) => {
  const d = toDate(iso);
  return d ? d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }) : "";
};

export const dayKey = (iso) => {
  const d = toDate(iso);
  return d ? startOfDay(d) : 0;
};

export const dayLabel = (iso, now = Date.now()) => {
  const d = toDate(iso);
  if (!d) return "";
  if (startOfDay(d) === startOfDay(new Date(now))) return t("thread.today", "Today");
  if (startOfDay(d) === startOfDay(new Date(now - DAY))) return t("thread.yesterday", "Yesterday");
  return d.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short", year: "numeric" });
};

const compactDuration = (ms) => {
  if (ms >= HOUR) return t("time.hours_short", "%{count}h", { count: Math.floor(ms / HOUR) });
  return t("time.minutes_short", "%{count}m", { count: Math.max(1, Math.floor(ms / MINUTE)) });
};

export const windowState = (conversation, now = Date.now()) => {
  const expires = toDate(conversation?.window_expires_at);
  const remaining = expires ? expires.getTime() - now : 0;
  const open = !!conversation?.window_open && remaining > 0;
  return { open, remaining, left: open ? compactDuration(remaining) : null, urgent: open && remaining < 2 * HOUR };
};

export const formatDuration = (seconds) => {
  if (seconds === null || seconds === undefined) return "—";
  const s = Math.max(0, Math.round(Number(seconds)));
  if (s < 60) return t("time.seconds_short", "%{count}s", { count: s });
  const minutes = Math.floor(s / 60);
  if (minutes < 60) return t("time.minutes_short", "%{count}m", { count: minutes });
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest
    ? t("time.hours_minutes_short", "%{hours}h %{minutes}m", { hours, minutes: rest })
    : t("time.hours_short", "%{count}h", { count: hours });
};

export const phoneDisplay = (customer) => {
  if (customer?.phone_display) return customer.phone_display;
  const digits = String(customer?.wa_id || "").replace(/\D/g, "");
  return digits ? `+${digits}` : "";
};

export const customerName = (customer) => customer?.name || phoneDisplay(customer);

export const initials = (name) =>
  String(name || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0].toUpperCase())
    .join("");

export const formatMoney = (amount, currency) => {
  const value = Number(amount || 0);
  try {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: currency || "INR",
      maximumFractionDigits: 0,
    }).format(value);
  } catch (e) {
    return `${currency || ""} ${Math.round(value).toLocaleString("en-IN")}`.trim();
  }
};

export const formatFileSize = (bytes) => {
  const n = Number(bytes || 0);
  if (!n) return "";
  if (n < 1024 * 1024) return `${Math.max(1, Math.round(n / 1024))} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
};

export const substituteVariables = (text, variables = {}) =>
  String(text || "").replace(/\{\{\s*([a-z_]+)\s*\}\}/gi, (match, key) => {
    const value = variables?.[key.toLowerCase()];
    return value === undefined || value === null || value === "" ? match : String(value);
  });

export const fillTemplate = (body, params = {}) =>
  String(body || "").replace(/\{\{\s*(\w+)\s*\}\}/g, (match, key) => (params[key] ? params[key] : match));

export const safeExternalUrl = (url) => (/^https?:\/\//i.test(String(url || "").trim()) ? String(url).trim() : null);

export const copyText = async (text) => {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch (e) {
    // The Shopify admin iframe often denies the async clipboard API.
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    let ok = false;
    try {
      ok = document.execCommand("copy");
    } catch (err) {
      ok = false;
    }
    document.body.removeChild(area);
    return ok;
  }
};

export const errorMessage = (error) => {
  switch (error?.code) {
    case "window_closed":
      return t("composer.window_closed_title", "The 24-hour reply window has closed");
    case "not_ready":
      return t("composer.not_ready", "Your WhatsApp number isn't ready to send");
    case "send_failed":
      return error.metaCode
        ? t("thread.failed_reason", "WhatsApp didn't accept this message (code %{code})", { code: error.metaCode })
        : error.message;
    default:
      return error?.message || t("errors.generic", "Something went wrong. Please try again.");
  }
};
