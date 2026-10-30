import axios from "axios";

/**
 * Data layer of the COD Form admin screens (ARCHITECTURE H.3, D.14–D.16).
 *
 * Every admin endpoint of the module is called from this file and nowhere
 * else, so a contract change is a one-file fix.
 *
 * Unlike Services/Api.js this instance does NOT run humps: the payloads carry
 * map keys (country codes, locales, text keys) that must not be re-cased.
 * JSON is snake_case in both directions.
 */
const instance = axios.create({ baseURL: "/cod_form" });

instance.interceptors.request.use(async (config) => {
  try {
    const token = await window.shopify.idToken();
    config.headers.Authorization = `Bearer ${token}`;
  } catch (error) {
    console.error("Failed to retrieve Shopify ID token", error);
  }
  const csrfMeta = document.querySelector('meta[name="csrf-token"]');
  if (csrfMeta) {
    config.headers["X-CSRF-Token"] = csrfMeta.getAttribute("content");
  }
  return config;
});

const data = (promise) => promise.then((response) => response.data);

const compact = (params) => {
  const out = {};
  Object.keys(params || {}).forEach((key) => {
    const value = params[key];
    if (value !== undefined && value !== null && value !== "") out[key] = value;
  });
  return out;
};

/* Generic verbs. Paths are relative to /cod_form. */
export const get = (path, params) => data(instance.get(path, { params: compact(params) }));
/* Every write tells the "not published" bar of the screen to look again. */
export const SAVED_EVENT = "codf:saved";
const saved = (promise) =>
  promise.then((result) => {
    try {
      window.dispatchEvent(new Event(SAVED_EVENT));
    } catch (error) {
      /* old browsers: the bar still re-checks on its timer */
    }
    return result;
  });
export const post = (path, body) => saved(data(instance.post(path, body || {})));
export const put = (path, body) => saved(data(instance.put(path, body || {})));
export const del = (path) => saved(data(instance.delete(path)));
export const upload = (path, formData) =>
  data(instance.post(path, formData, { headers: { "Content-Type": "multipart/form-data" } }));
export const download = (path, params) =>
  instance.get(path, { params: compact(params), responseType: "blob" }).then((response) => response.data);

/**
 * Normalised error of an admin API call (D.14):
 *   422 {"error":"validation_failed","errors":{"<path>":["message"]}}
 *   402 {"error":"upgrade_required","feature":"order_bumps","min_tier":"pro"}
 *   403 {"error":"module_disabled"}   404 {"error":"not_found"}
 */
export const parseError = (error) => {
  const response = error && error.response;
  const body = response && response.data && typeof response.data === "object" ? response.data : {};
  const errors = body.errors && typeof body.errors === "object" ? body.errors : {};
  const messages = [];
  Object.keys(errors).forEach((path) => {
    [].concat(errors[path] || []).forEach((message) => messages.push({ path, message: String(message) }));
  });
  return {
    status: response ? response.status : 0,
    code: body.error || (response ? "http_error" : "network_error"),
    errors,
    messages,
    feature: body.feature || null,
    minTier: body.min_tier || null,
    isValidation: !!response && response.status === 422,
    isGate: !!response && response.status === 402,
    isNotFound: !!response && response.status === 404,
    isModuleDisabled: !!response && response.status === 403 && body.error === "module_disabled",
  };
};

/* UI route segment ↔ cod_offers.offer_type */
export const OFFER_TYPE_BY_SEGMENT = {
  quantity: "quantity",
  bumps: "bump",
  upsells: "upsell",
  downsells: "downsell",
  thresholds: "threshold",
};

/* ── Endpoints, one function per row of D.15 ─────────────────────────── */
export const codFormApi = {
  bootstrap: () => get("/bootstrap"),

  setup: {
    show: () => get("/setup"),
    update: (general) => put("/setup", { general }),
    mode: (mode) => post("/mode", { mode }),
    refreshEmbed: () => post("/setup/refresh_embed"),
    testOrder: () => post("/setup/test_order"),
    dismissOptin: () => post("/setup/dismiss_optin"),
  },

  /* Has what was saved reached the storefront? (shop metafield written by a background job) */
  sync: {
    show: () => get("/sync"),
    publish: () => post("/sync"),
  },

  button: {
    show: () => get("/button"),
    update: ({ preset, config }) => put("/button", { preset, config }),
  },

  forms: {
    index: () => get("/forms"),
    defaults: () => get("/forms/defaults"),
    show: (id) => get(`/forms/${id}`),
    create: ({ name, template_key, targeting }) => post("/forms", { name, template_key, targeting }),
    update: (id, { name, targeting, draft_config }) => put(`/forms/${id}`, { name, targeting, draft_config }),
    publish: (id) => post(`/forms/${id}/publish`),
    discardDraft: (id) => post(`/forms/${id}/discard_draft`),
    duplicate: (id) => post(`/forms/${id}/duplicate`),
    makeDefault: (id) => post(`/forms/${id}/make_default`),
    destroy: (id) => del(`/forms/${id}`),
  },

  shippingRates: {
    index: () => get("/shipping_rates"),
    create: (rate) => post("/shipping_rates", rate),
    update: (id, rate) => put(`/shipping_rates/${id}`, rate),
    destroy: (id) => del(`/shipping_rates/${id}`),
    reorder: (ids) => post("/shipping_rates/reorder", { ids }),
    importCsv: (file, mode) => {
      const formData = new FormData();
      formData.append("file", file);
      formData.append("mode", mode === "replace" ? "replace" : "append");
      return upload("/shipping_rates/import_csv", formData);
    },
  },

  offers: {
    index: (offerType) => get("/offers", { type: offerType }),
    show: (id) => get(`/offers/${id}`),
    create: (offer) => post("/offers", offer),
    update: (id, offer) => put(`/offers/${id}`, offer),
    destroy: (id) => del(`/offers/${id}`),
    status: (id, status) => post(`/offers/${id}/status`, { status }),
  },

  abTests: {
    index: () => get("/ab_tests"),
    show: (id) => get(`/ab_tests/${id}`),
    create: (test) => post("/ab_tests", test),
    update: (id, test) => put(`/ab_tests/${id}`, test),
    destroy: (id) => del(`/ab_tests/${id}`),
    start: (id) => post(`/ab_tests/${id}/start`),
    stop: (id) => post(`/ab_tests/${id}/stop`),
  },

  fraud: {
    show: () => get("/fraud"),
    update: ({ fraud, otp, rto }) => put("/fraud", { fraud, otp, rto }),
  },

  blockEntries: {
    index: ({ kind, q, page }) => get("/block_entries", { kind, q, page }),
    create: ({ kind, value, note }) => post("/block_entries", { kind, value, note }),
    createBulk: ({ kind, values }) => post("/block_entries", { kind, values }),
    destroy: (id) => del(`/block_entries/${id}`),
  },

  rejections: {
    index: ({ page, reason }) => get("/rejections", { page, reason }),
  },

  pixels: {
    index: () => get("/pixels"),
    create: (pixel) => post("/pixels", pixel),
    update: (id, pixel) => put(`/pixels/${id}`, pixel),
    destroy: (id) => del(`/pixels/${id}`),
    test: (id) => post(`/pixels/${id}/test`),
  },

  integrations: {
    index: () => get("/integrations"),
    update: (provider, { credentials, config }) =>
      put(`/integrations/${provider}`, compact({ credentials, config })),
    destroy: (provider) => del(`/integrations/${provider}`),
    googleAuthUrl: () => get("/integrations/google_sheets/auth_url"),
    googleSheets: () => get("/integrations/google_sheets/sheets"),
  },

  analytics: {
    show: ({ from, to, country, device, product_id, compare }) =>
      get("/analytics", { from, to, country, device, product_id, compare: compare ? 1 : undefined }),
    sessions: ({ from, to, country, device, recent }) => get("/analytics/sessions", { from, to, country, device, recent }),
    breakdown: ({ by, from, to }) => get("/analytics/breakdown", { by, from, to }),
    exportCsv: ({ from, to, country, device, product_id }) =>
      download("/analytics/export.csv", { from, to, country, device, product_id }),
  },

  usage: {
    show: () => get("/usage"),
  },
};

export default codFormApi;
