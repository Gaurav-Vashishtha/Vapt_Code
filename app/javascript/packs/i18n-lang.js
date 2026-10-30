import I18n from "i18n-js";
import en from "../../../config/localeJson/en.json";
import es from "../../../config/localeJson/es.json";
// import hi from "../../../config/localeJson/hi.json"; // Example: Hindi
// import ar from "../../../config/localeJson/ar.json"; // Example: Arabic
import ur from "../../../config/localeJson/ur.json";
import de from "../../../config/localeJson/de.json";
import ar from "../../../config/localeJson/ar.json";
import hi from "../../../config/localeJson/hi.json";
import cs from "../../../config/localeJson/cs.json";
import tr from "../../../config/localeJson/tr.json";
import zh from "../../../config/localeJson/zh.json";
import it from "../../../config/localeJson/it.json";

I18n.translations = {
  en,
  es,
  ur,
  de,
  ar,
  hi,
  cs,
  tr,
  zh,
  it,
};

I18n.locale = "en";
I18n.defaultLocale = "en";
I18n.fallbacks = true;

export default I18n;
