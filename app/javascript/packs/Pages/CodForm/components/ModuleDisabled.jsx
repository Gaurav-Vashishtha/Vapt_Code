import React from "react";
import { Page } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { t } from "../i18n";
import EmptyState from "./EmptyState";

/** Shown when a COD Form URL is opened by a shop that does not have the module (NFR-12). */
const ModuleDisabled = () => (
  <Page fullWidth title={t("common.module_title", "COD Form")}>
    <EmptyState
      heading={t("common.module_disabled_title", "COD Form is not available for this store yet")}
      action={{ content: t("common.module_disabled_cta", "Contact support"), onAction: () => navigateTo("/help-and-support") }}
    >
      <p>{t("common.module_disabled_long", "COD Form is being rolled out store by store. Message us from Help & Support and we will turn it on for you.")}</p>
    </EmptyState>
  </Page>
);

export default ModuleDisabled;
