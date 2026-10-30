import { codFormApi } from "../api";
import { DEFAULT_FORM_CONFIG, FALLBACK_TEMPLATES, FALLBACK_TEXTS } from "../defaults";

/* GET /cod_form/forms/defaults, fetched once per page load:
   {config, templates, texts: {en: {...}, hi: {...}}, countries: [{code, name}]} */
let promise = null;

const shape = (raw) => {
  const body = raw && typeof raw === "object" ? raw : {};
  const texts = body.texts && typeof body.texts === "object" ? body.texts : {};
  return {
    config: body.config && typeof body.config === "object" ? body.config : DEFAULT_FORM_CONFIG,
    templates: Array.isArray(body.templates) && body.templates.length ? body.templates : FALLBACK_TEMPLATES,
    texts: { ...texts, en: { ...FALLBACK_TEXTS, ...(texts.en || {}) } },
    countries: Array.isArray(body.countries) ? body.countries : [],
  };
};

export const loadFormDefaults = () => {
  if (!promise) {
    promise = codFormApi.forms
      .defaults()
      .then(shape)
      .catch(() => {
        promise = null;
        return shape({});
      });
  }
  return promise;
};

export default loadFormDefaults;
