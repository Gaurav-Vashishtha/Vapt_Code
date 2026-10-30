import React, { useContext, useEffect } from "react";
import { SaveBar } from "@shopify/app-bridge-react";
import I18n from "../../../i18n-lang";
import { StoreContext } from "../../../Context/Store";

/**
 * The contextual save bar every editable COD Form screen uses
 * (App Bridge v4 <SaveBar>, same markup as Components/CODFeesSettings.jsx).
 * It also raises the store's `contextualBar` flag while open, which is what
 * makes the app block back-navigation with unsaved changes.
 */
const ScreenSaveBar = ({ open, saving, onSave, onDiscard, saveLabel, discardLabel }) => {
  const store = useContext(StoreContext);
  const setContextualBar = store && store.contextualBar ? store.contextualBar[1] : null;

  useEffect(() => {
    if (!setContextualBar) return undefined;
    setContextualBar(!!open);
    return () => setContextualBar(false);
  }, [open, setContextualBar]);

  return (
    <SaveBar data-save-bar open={!!open}>
      <button
        variant="primary"
        onClick={onSave}
        loading={saving ? "" : undefined}
        disabled={saving}
      >
        {saveLabel || I18n.t("admin.save")}
      </button>
      <button onClick={onDiscard} disabled={saving}>
        {discardLabel || I18n.t("admin.discard")}
      </button>
    </SaveBar>
  );
};

export default ScreenSaveBar;
