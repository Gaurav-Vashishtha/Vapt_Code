import React, { useCallback, useEffect, useState } from "react";
import { Badge, Banner, BlockStack, Button, Card, Divider, InlineStack, Modal, Select, Text, TextField } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { codFormApi, parseError } from "../api";
import { useGate, UpgradeCard } from "../components/Gate";
import Screen, { SaveErrorBanner } from "../components/Screen";
import EmptyState from "../components/EmptyState";
import { FEATURES, LIMITS, PATHS } from "../constants";
import { formatDateTime } from "../utils";
import { t } from "../i18n";
import loadFormDefaults from "./formDefaults";

/** /features/cod-form/designer/forms — up to five forms, one default (FRM-22). */
const FormsListPage = () => {
  const gate = useGate(FEATURES.MULTIPLE_FORMS);
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [busy, setBusy] = useState(null);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [templateKey, setTemplateKey] = useState("classic");
  const [templates, setTemplates] = useState([]);
  const [confirmDelete, setConfirmDelete] = useState(null);

  const load = useCallback(() => {
    setError(null);
    return codFormApi.forms
      .index()
      .then((response) => setItems((response && response.items) || []))
      .catch((err) => setError(parseError(err)));
  }, []);

  useEffect(() => {
    load();
    loadFormDefaults().then((defaults) => setTemplates(defaults.templates || []));
  }, [load]);

  const forms = (items || []).filter((form) => form.status !== "archived");
  const atLimit = forms.length >= LIMITS.FORMS_MAX;
  const needsGate = forms.length >= LIMITS.FORMS_WITHOUT_GATE && !gate.allowed;

  const run = (key, action) => {
    setBusy(key);
    setActionError(null);
    return action()
      .then(() => load())
      .catch((err) => setActionError(parseError(err)))
      .then(() => setBusy(null));
  };

  const create = () =>
    run("create", () =>
      codFormApi.forms
        .create({ name: name.trim(), template_key: templateKey, targeting: { product_ids: [], collection_ids: [] } })
        .then((form) => {
          setCreating(false);
          setName("");
          if (form && form.id) navigateTo(`${PATHS.designer}/${form.id}`);
        }),
    );

  return (
    <Screen
      title={t("designer.forms_title", "Forms")}
      subtitle={t("designer.forms_subtitle", "Use different forms for different products. The default form covers everything else.")}
      backPath={PATHS.designer}
      backLabel={t("designer.title", "Form designer")}
      primaryAction={{
        content: t("designer.new_form", "New form"),
        onAction: () => setCreating(true),
        disabled: atLimit || needsGate,
      }}
      loading={items === null && !error}
      error={error}
      onRetry={load}
    >
      <SaveErrorBanner error={actionError} onDismiss={() => setActionError(null)} />
      {needsGate && (
        <UpgradeCard
          minTier={gate.minTier}
          title={t("designer.multiple_forms_locked", "More than one form")}
          description={t("designer.multiple_forms_locked_body", "Your plan includes one form. Upgrade to use up to 5 forms, each for its own products or collections.")}
        />
      )}
      {atLimit && !needsGate && (
        <Banner tone="info">
          <p>{t("designer.forms_limit", "You have reached the limit of 5 forms. Archive one to add another.")}</p>
        </Banner>
      )}

      {forms.length === 0 ? (
        <EmptyState
          heading={t("designer.forms_empty_title", "No form yet")}
          action={{ content: t("designer.new_form", "New form"), onAction: () => setCreating(true) }}
        >
          <p>{t("designer.forms_empty_body", "Your default form is created when you turn on COD Form in Setup. You can also create one now.")}</p>
        </EmptyState>
      ) : (
        <Card>
          <BlockStack gap="300">
            {forms.map((form, index) => (
              <React.Fragment key={form.id}>
                {index > 0 && <Divider />}
                <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
                  <BlockStack gap="100">
                    <InlineStack gap="200" blockAlign="center" wrap>
                      <Text as="h3" variant="headingSm">
                        {form.name}
                      </Text>
                      {form.is_default && <Badge tone="info">{t("designer.default_badge", "Default")}</Badge>}
                      {!form.published_version ? (
                        <Badge tone="attention">{t("designer.not_published", "Not published yet")}</Badge>
                      ) : form.has_unpublished_changes ? (
                        <Badge tone="attention">{t("designer.unpublished_changes", "Unpublished changes")}</Badge>
                      ) : (
                        <Badge tone="success">{t("designer.published", "Published")}</Badge>
                      )}
                    </InlineStack>
                    <Text as="p" variant="bodySm" tone="subdued">
                      {form.is_default
                        ? t("designer.form_targets_default", "All products without another form")
                        : t("designer.form_targets_count", "%{products} products · %{collections} collections", {
                            products: ((form.targeting && form.targeting.product_ids) || []).length,
                            collections: ((form.targeting && form.targeting.collection_ids) || []).length,
                          })}
                      {form.published_at ? ` · ${t("designer.published_at", "Last published %{date}", { date: formatDateTime(form.published_at) })}` : ""}
                    </Text>
                  </BlockStack>
                  <InlineStack gap="200" wrap>
                    <Button variant="primary" onClick={() => navigateTo(`${PATHS.designer}/${form.id}`)}>
                      {t("common.edit", "Edit")}
                    </Button>
                    <Button
                      loading={busy === `dup-${form.id}`}
                      disabled={atLimit || !gate.allowed}
                      onClick={() => run(`dup-${form.id}`, () => codFormApi.forms.duplicate(form.id))}
                    >
                      {t("designer.duplicate", "Duplicate")}
                    </Button>
                    {!form.is_default && (
                      <Button
                        loading={busy === `def-${form.id}`}
                        onClick={() => run(`def-${form.id}`, () => codFormApi.forms.makeDefault(form.id))}
                      >
                        {t("designer.make_default", "Make default")}
                      </Button>
                    )}
                    {!form.is_default && (
                      <Button tone="critical" onClick={() => setConfirmDelete(form)}>
                        {t("designer.archive", "Archive")}
                      </Button>
                    )}
                  </InlineStack>
                </InlineStack>
              </React.Fragment>
            ))}
          </BlockStack>
        </Card>
      )}

      <Modal
        open={creating}
        onClose={() => setCreating(false)}
        title={t("designer.new_form", "New form")}
        primaryAction={{
          content: t("designer.create_form", "Create form"),
          onAction: create,
          loading: busy === "create",
          disabled: name.trim() === "",
        }}
        secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: () => setCreating(false) }]}
      >
        <Modal.Section>
          <BlockStack gap="400">
            <TextField
              label={t("designer.form_name", "Form name")}
              value={name}
              onChange={setName}
              maxLength={80}
              autoComplete="off"
            />
            {templates.length > 0 && (
              <Select
                label={t("designer.start_from_template", "Start from template")}
                options={templates.map((template) => ({ value: template.key, label: template.name || template.key }))}
                value={templateKey}
                onChange={setTemplateKey}
              />
            )}
            <Text as="p" variant="bodySm" tone="subdued">
              {t("designer.new_form_help", "Choose its products or collections on the Form tab after creating it.")}
            </Text>
          </BlockStack>
        </Modal.Section>
      </Modal>

      <Modal
        open={!!confirmDelete}
        onClose={() => setConfirmDelete(null)}
        title={t("designer.archive_title", "Archive this form?")}
        primaryAction={{
          content: t("designer.archive", "Archive"),
          destructive: true,
          loading: !!confirmDelete && busy === `del-${confirmDelete.id}`,
          onAction: () => {
            const form = confirmDelete;
            run(`del-${form.id}`, () => codFormApi.forms.destroy(form.id)).then(() => setConfirmDelete(null));
          },
        }}
        secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: () => setConfirmDelete(null) }]}
      >
        <Modal.Section>
          <Text as="p">
            {t("designer.archive_body", "Products that used \"%{name}\" go back to your default form.", { name: confirmDelete ? confirmDelete.name : "" })}
          </Text>
        </Modal.Section>
      </Modal>
    </Screen>
  );
};

export default FormsListPage;
