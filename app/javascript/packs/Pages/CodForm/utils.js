/* Small pure helpers shared by the COD Form screens. */

export const isPlainObject = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

export const clone = (value) =>
  value === undefined ? value : JSON.parse(JSON.stringify(value));

export const deepEqual = (a, b) => {
  if (a === b) return true;
  if (a == null || b == null) return a == null && b == null;
  if (typeof a !== typeof b) return false;
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) return false;
    for (let i = 0; i < a.length; i += 1) {
      if (!deepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (isPlainObject(a)) {
    if (!isPlainObject(b)) return false;
    // A key set to undefined is the same as a missing key (JSON drops it, so a saved copy
    // never has it): without this a freshly loaded screen could look edited.
    const keysA = Object.keys(a).filter((key) => a[key] !== undefined);
    const keysB = Object.keys(b).filter((key) => b[key] !== undefined);
    if (keysA.length !== keysB.length) return false;
    for (let i = 0; i < keysA.length; i += 1) {
      const key = keysA[i];
      if (!Object.prototype.hasOwnProperty.call(b, key)) return false;
      if (!deepEqual(a[key], b[key])) return false;
    }
    return true;
  }
  return false;
};

/** Read a nested value: getIn(obj, ["a", "b"], fallback). */
export const getIn = (object, path, fallback) => {
  let current = object;
  for (let i = 0; i < path.length; i += 1) {
    if (current == null) return fallback;
    current = current[path[i]];
  }
  return current === undefined ? fallback : current;
};

/** Immutable nested write; creates objects along the way. */
export const setIn = (object, path, value) => {
  if (!path.length) return value;
  const [head, ...rest] = path;
  const base = Array.isArray(object)
    ? [...object]
    : { ...(isPlainObject(object) ? object : {}) };
  base[head] = setIn(base[head], rest, value);
  return base;
};

/**
 * Fill missing keys from `defaults`, deeply. Arrays and scalars of `value`
 * win as they are; unknown keys of `value` are kept (the server drops them).
 */
export const mergeDefaults = (defaults, value) => {
  if (!isPlainObject(defaults)) return value === undefined ? defaults : value;
  const source = isPlainObject(value) ? value : {};
  const out = { ...source };
  Object.keys(defaults).forEach((key) => {
    out[key] = mergeDefaults(defaults[key], source[key]);
  });
  return out;
};

export const moveItem = (list, from, to) => {
  if (from === to || from < 0 || to < 0 || from >= list.length || to >= list.length) {
    return list;
  }
  const next = [...list];
  const [item] = next.splice(from, 1);
  next.splice(to, 0, item);
  return next;
};

const ALNUM = "abcdefghijklmnopqrstuvwxyz0123456789";
export const randomKey = (length = 8) => {
  let out = "";
  for (let i = 0; i < length; i += 1) {
    out += ALNUM[Math.floor(Math.random() * ALNUM.length)];
  }
  return out;
};

export const toInt = (value, fallback = null) => {
  if (value === "" || value === null || value === undefined) return fallback;
  const parsed = parseInt(value, 10);
  return Number.isNaN(parsed) ? fallback : parsed;
};

export const toNumber = (value, fallback = null) => {
  if (value === "" || value === null || value === undefined) return fallback;
  const parsed = Number(value);
  return Number.isNaN(parsed) ? fallback : parsed;
};

export const isInternalPath = (url) =>
  typeof url === "string" && url.startsWith("/") && !url.startsWith("//");

/** Split pasted text (commas, semicolons, new lines) into trimmed unique entries. */
export const splitEntries = (text) => {
  const seen = new Set();
  const out = [];
  String(text || "")
    .split(/[\n,;]+/)
    .map((entry) => entry.trim())
    .filter(Boolean)
    .forEach((entry) => {
      const key = entry.toLowerCase();
      if (!seen.has(key)) {
        seen.add(key);
        out.push(entry);
      }
    });
  return out;
};

export const formatDateTime = (iso) => {
  if (!iso) return "";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString();
};

export const todayIso = (offsetDays = 0) => {
  const date = new Date();
  date.setDate(date.getDate() + offsetDays);
  return date.toISOString().slice(0, 10);
};

/* ── Colour contrast (WCAG 2.1) for the designer warning ─────────────── */
const hexToRgb = (hex) => {
  const match = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(hex || "").trim());
  if (!match) return null;
  let value = match[1];
  if (value.length === 3) value = value.split("").map((c) => c + c).join("");
  return [0, 2, 4].map((i) => parseInt(value.slice(i, i + 2), 16));
};

const luminance = (rgb) => {
  const [r, g, b] = rgb.map((channel) => {
    const c = channel / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

export const isHexColor = (value) => hexToRgb(value) !== null;

/** Contrast ratio 1..21, or null when either colour is not a hex value. */
export const contrastRatio = (foreground, background) => {
  const fg = hexToRgb(foreground);
  const bg = hexToRgb(background);
  if (!fg || !bg) return null;
  const l1 = luminance(fg);
  const l2 = luminance(bg);
  const [light, dark] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (light + 0.05) / (dark + 0.05);
};

/* ── Postal list syntax, same rules as CodForm::Engine::PostalMatcher ─── */
const normalizePostal = (code) =>
  String(code || "").toUpperCase().replace(/[\s-]/g, "");

export const parsePostalList = (list) =>
  String(Array.isArray(list) ? list.join(",") : list || "")
    .split(/[,;\n]+/)
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      if (entry.endsWith("*") && entry.length > 1) {
        return { type: "prefix", value: normalizePostal(entry.slice(0, -1)) };
      }
      const dash = entry.indexOf("-");
      if (dash > 0 && dash === entry.lastIndexOf("-")) {
        const from = normalizePostal(entry.slice(0, dash));
        const to = normalizePostal(entry.slice(dash + 1));
        if (/^\d+$/.test(from) && /^\d+$/.test(to) && from.length === to.length) {
          return { type: "range", from, to };
        }
      }
      return { type: "exact", value: normalizePostal(entry) };
    });

export const postalListSummary = (list) => {
  const entries = parsePostalList(list);
  return {
    total: entries.length,
    exact: entries.filter((entry) => entry.type === "exact").length,
    patterns: entries.filter((entry) => entry.type !== "exact").length,
  };
};

/** plans.cod_form_orders at or above this is shown as "Unlimited" (same rule as CapService). */
export const UNLIMITED_FORM_ORDERS = 100000;
export const isUnlimitedFormOrders = (count) => Number(count) >= UNLIMITED_FORM_ORDERS;
