import React, { useContext, useState, useCallback, useEffect } from "react";
import { Select } from "@shopify/polaris";
import { SaveBar } from "@shopify/app-bridge-react";
import I18n from "../../i18n-lang";
import { StoreContext, applyTextDirection } from "../../Context/Store";
import Api from "../../Services/Api";

const LanguageDropdown = ({
  shouldSubmitLanguage,
  onLanguageSubmitted,
  /** When true (e.g. Quick Onboarding), save language in background and do not show the contextual save bar */
  silentSave = false,
}) => {
  const store = useContext(StoreContext);

  if (!store || !store.setting) return null;

  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    contextualBar: [contextualBar, setContextualBar],
  } = store;

  const [selectedLang, setSelectedLang] = useState(
    setting?.selectedLocale || "en"
  );
  const [saving, setSaving] = useState(false);

  // Keep dropdown in sync with server setting when not in "unsaved" state
  useEffect(() => {
    if (!contextualBar) {
      const serverLocale = setting?.selectedLocale || "en";
      setSelectedLang(serverLocale);
      I18n.locale = serverLocale;
      applyTextDirection(serverLocale);
    }
  }, [setting?.selectedLocale, contextualBar]);

  // Save language to backend only (no localStorage). Used by both silentSave and Save bar.
  const persistLocale = useCallback(
    async (localeValue) => {
      const updatedSetting = {
        ...originalSetting,
        selectedLocale: localeValue,
      };
      const resp = await Api.post("/settings", { setting: updatedSetting });
      if (resp?.data) {
        setSetting(resp.data);
        setOriginalSetting(resp.data);
      }
      return resp;
    },
    [originalSetting, setSetting, setOriginalSetting]
  );

  // Sync state when dropdown changes
  const handleChange = async (value) => {
    setSelectedLang(value);
    I18n.locale = value;
    applyTextDirection(value);

    setSetting((prev) => ({
      ...prev,
      selectedLocale: value,
    }));

    if (silentSave) {
      try {
        await persistLocale(value);
        if (typeof onLanguageSubmitted === "function") {
          onLanguageSubmitted(value);
        }
      } catch (error) {
        console.error("Language save failed:", error);
      }
      return;
    }

    setContextualBar(true);
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await persistLocale(selectedLang);
      setContextualBar(false);
    } catch (error) {
      console.error("Save failed:", error);
      setContextualBar(false);
    } finally {
      setSaving(false);
    }
  };

  const handleDiscard = () => {
    const fallback = originalSetting?.selectedLocale || "en";
    setSelectedLang(fallback);
    setSetting({ ...originalSetting });
    I18n.locale = fallback;
    applyTextDirection(fallback);
    setContextualBar(false);
  };

  return (
    <>
      {!silentSave && (
        <SaveBar id="my-save-bar" data-save-bar open={contextualBar}>
          <button
            variant="primary"
            onClick={handleSave}
            loading={saving ? "" : undefined}
            disabled={saving}
          >
            {I18n.t("admin.save")}
          </button>
          <button onClick={handleDiscard} disabled={saving}>
            {I18n.t("admin.discard")}
          </button>
        </SaveBar>
      )}

      <div style={{ maxWidth: 250, marginBottom: 16 }}>
        <Select
          label={I18n.t("language_dropdown.language_label")}
          options={[
            { label: I18n.t("language_dropdown.languages.english"), value: "en" },
            { label: I18n.t("language_dropdown.languages.spanish"), value: "es" },
            { label: I18n.t("language_dropdown.languages.urdu"), value: "ur" },
            { label: I18n.t("language_dropdown.languages.german"), value: "de" },
            { label: I18n.t("language_dropdown.languages.arabic"), value: "ar" },
            { label: I18n.t("language_dropdown.languages.turkish"), value: "tr" },
            { label: I18n.t("language_dropdown.languages.czech"), value: "cs" },
            { label: I18n.t("language_dropdown.languages.hindi"), value: "hi" },
            { label: I18n.t("language_dropdown.languages.italian"), value: "it" },
          ]}
          value={selectedLang}
          onChange={handleChange}
          disabled={saving}
        />
      </div>
    </>
  );
};

export default LanguageDropdown;