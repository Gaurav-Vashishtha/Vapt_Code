import I18n from "../../i18n-lang";

/**
 * Translation helpers for the COD Form module.
 *
 * `t("setup.title", "Setup")` reads `cod_form.setup.title` from
 * config/localeJson/en.json and falls back to the English text given here, so
 * a screen never renders a raw key while Crowdin catches up.
 * Variables use the i18n-js form: "%{count}".
 *
 * Keys and fallbacks must be string literals: the en.json section is generated
 * from these calls.
 */
export const t = (key, fallback, vars) =>
  I18n.t(`cod_form.${key}`, { defaultValue: fallback, ...(vars || {}) });

/** Same, for keys outside the `cod_form` section (settings_hub, integrations…). */
export const tg = (key, fallback, vars) =>
  I18n.t(key, { defaultValue: fallback, ...(vars || {}) });

export default t;
