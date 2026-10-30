import React, { useCallback, useEffect, useState } from "react";
import { navigateTo } from "../../../../utils/navigate";
import { codFormApi, parseError } from "../api";
import Screen from "../components/Screen";
import EmptyState from "../components/EmptyState";
import { PATHS } from "../constants";
import { t } from "../i18n";
import DesignerPage from "./DesignerPage";
import FormsListPage from "./FormsListPage";

/**
 * /features/cod-form/designer: the forms list when the shop has more than one
 * form, otherwise the designer for its default form (H.4).
 */
const DesignerRoute = () => {
  const [forms, setForms] = useState(null);
  const [error, setError] = useState(null);
  const [creating, setCreating] = useState(false);

  const load = useCallback(() => {
    setError(null);
    codFormApi.forms
      .index()
      .then((response) => setForms(((response && response.items) || []).filter((form) => form.status !== "archived")))
      .catch((err) => setError(parseError(err)));
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  if (forms && forms.length > 1) return <FormsListPage />;
  if (forms && forms.length === 1) return <DesignerPage formId={forms[0].id} />;

  const createDefault = () => {
    setCreating(true);
    codFormApi.forms
      .create({ name: "Default form", template_key: "classic", targeting: { product_ids: [], collection_ids: [] } })
      .then(() => load())
      .catch((err) => setError(parseError(err)))
      .then(() => setCreating(false));
  };

  return (
    <Screen
      title={t("designer.title", "Form designer")}
      loading={forms === null && !error}
      error={error}
      onRetry={load}
    >
      <EmptyState
        heading={t("designer.no_form_title", "Your form is not created yet")}
        action={{ content: t("designer.create_form", "Create form"), onAction: createDefault, loading: creating }}
        secondaryAction={{ content: t("designer.go_to_setup", "Go to Setup"), onAction: () => navigateTo(PATHS.setup) }}
      >
        <p>{t("designer.no_form_body", "The default form is created when you turn on COD Form in Setup. You can also create it now and design it before going live.")}</p>
      </EmptyState>
    </Screen>
  );
};

export default DesignerRoute;
