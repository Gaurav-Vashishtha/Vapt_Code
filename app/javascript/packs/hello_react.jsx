import React from "react";
import { createRoot } from "react-dom/client";
import { AppProvider } from "@shopify/polaris";
// Remove AppBridgeProvider import
import enTranslations from "@shopify/polaris/locales/en.json";

import Home from "./Pages/Home";
import StoreProvicer from "./Context/Store";
import SettingUp from "./SettingUp";
import ReconnectedNotice from "./ReconnectedNotice";
import { installHubUrlRewrite } from "./Pages/SettingsHub/hubUrl";

// Before anything navigates: settings URLs are shown under /settings-hub.
installHubUrlRewrite();

const Hello = (props) => {
  return (
    <AppProvider i18n={enTranslations}>
      {/* No AppBridgeProvider needed here for v4!
          The script in your head handles the connection.
      */}
      {props.needs_bootstrap ? (
        // First install: no Admin token yet — mint it, then reload into the app.
        <SettingUp />
      ) : (
        <StoreProvicer {...props}>
          <Home />
          {props.reconnected ? <ReconnectedNotice /> : null}
        </StoreProvicer>
      )}
    </AppProvider>
  );
};

document.addEventListener("DOMContentLoaded", () => {
  const node = document.getElementById("hello-react");
  if (!node) return;
  const data = JSON.parse(node.getAttribute("data"));
  const root = createRoot(node);
  root.render(<Hello {...data} />);
});