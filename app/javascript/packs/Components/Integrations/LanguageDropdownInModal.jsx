import React, { useContext } from "react";
import LanguageDropdown from "./LanguageDropdown";
import { StoreContext } from "../../Context/Store";
import I18n from "../../i18n-lang";

const LanguageModalContent = () => {
  const store = useContext(StoreContext);

  // ⛔ store may not be initialized when modal renders early
  if (!store || !store.setting || !Array.isArray(store.setting)) {
    return <p>{I18n.t("language_dropdown_in_modal.loading_language_settings")}</p>; // fallback while StoreContext is not ready
  }

  const [setting] = store.setting;
  const selectedLocale = setting?.selectedLocale || "(empty)";

  return (
    <div style={{ padding: "10px" }}>
      <LanguageDropdown />
    </div>
  );
};

export default LanguageModalContent;
