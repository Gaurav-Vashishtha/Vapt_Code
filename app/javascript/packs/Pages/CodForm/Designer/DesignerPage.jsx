import React, { useCallback, useEffect, useMemo, useState } from "react";
import styled from "styled-components";
import { Banner, BlockStack, Card, InlineGrid, List, Tabs } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { codFormApi, parseError } from "../api";
import useResource from "../useResource";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { withFormDefaults } from "../defaults";
import { PATHS } from "../constants";
import { deepEqual } from "../utils";
import { t } from "../i18n";
import Screen, { SaveErrorBanner } from "../components/Screen";
import ScreenSaveBar from "../components/ScreenSaveBar";
import DevicePreview from "./DevicePreview";
import TemplatesModal from "./TemplatesModal";
import FormTargetingCard from "./FormTargetingCard";
import FieldsTab from "./tabs/FieldsTab";
import BlocksTab from "./tabs/BlocksTab";
import DesignTab from "./tabs/DesignTab";
import TextsTab from "./tabs/TextsTab";
import ThankYouTab from "./tabs/ThankYouTab";
import loadFormDefaults from "./formDefaults";

const StickyColumn = styled.div`
  @media (min-width: 1040px) {
    position: sticky;
    top: 16px;
  }
`;

const prepare = (raw) => {
  const form = (raw && raw.form) || raw || {};
  return {
    form: {
      ...form,
      name: form.name || "",
      targeting: { product_ids: [], collection_ids: [], ...(form.targeting || {}) },
      draft_config: withFormDefaults(form.draft_config),
    },
    warnings: Array.isArray(form.warnings) ? form.warnings : [],
    // Optional extra of PUT /forms/:id: problems that will make publish answer 422.
    publishErrors: form.publish_errors,
  };
};

/** /features/cod-form/designer[/:id] — fields, blocks, design, texts, thank-you, draft / publish, live preview. */
const DesignerPage = ({ formId, showFormsLink }) => {
  const bootstrap = useCodFormBootstrap();
  const [defaults, setDefaults] = useState(null);
  const [tab, setTab] = useState(0);
  const [locale, setLocale] = useState("en");
  const [templatesOpen, setTemplatesOpen] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const [discarding, setDiscarding] = useState(false);
  const [actionError, setActionError] = useState(null);

  const resource = useResource({
    load: () =>
      Promise.all([codFormApi.forms.show(formId), loadFormDefaults()]).then(([form, formDefaults]) => {
        setDefaults(formDefaults);
        return { form };
      }),
    save: (data) =>
      codFormApi.forms
        .update(formId, { name: data.form.name, targeting: data.form.targeting, draft_config: data.form.draft_config })
        .then((form) => ({ form })),
    prepare,
    deps: [formId],
  });
  const { data, setData, original, isDirty, loading, saving, error, saveError, save, discard, reload, replace, clearSaveError } = resource;

  useEffect(() => {
    if (bootstrap && bootstrap.locales && bootstrap.locales.length && locale === "en" && !bootstrap.locales.includes("en")) {
      setLocale(bootstrap.locales[0]);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bootstrap]);

  const config = data ? data.form.draft_config : null;
  const defaultsTexts = defaults ? defaults.texts : null;

  const setConfig = useCallback(
    (next) =>
      setData((current) => ({
        ...current,
        form: {
          ...current.form,
          draft_config: typeof next === "function" ? next(current.form.draft_config) : next,
        },
      })),
    [setData],
  );

  const locales = useMemo(() => {
    const set = new Set([...(bootstrap ? bootstrap.locales : []), "en", ...Object.keys((config && config.texts) || {}), locale]);
    return Array.from(set);
  }, [bootstrap, config, locale]);

  const hasUnpublished = useMemo(() => {
    if (!original) return false;
    const form = original.form;
    if (!form.published_version) return true;
    if (typeof form.has_unpublished_changes === "boolean") return form.has_unpublished_changes;
    return !deepEqual(form.draft_config, withFormDefaults(form.published_config));
  }, [original]);

  const publish = useCallback(async () => {
    setActionError(null);
    setPublishing(true);
    try {
      if (isDirty) {
        const ok = await save();
        if (!ok) return;
      }
      const form = await codFormApi.forms.publish(formId);
      replace({ form: { ...form, has_unpublished_changes: false } });
      if (window.shopify && window.shopify.toast) {
        window.shopify.toast.show(t("designer.published_toast", "Form published"));
      }
    } catch (err) {
      setActionError(parseError(err));
    } finally {
      setPublishing(false);
    }
  }, [formId, isDirty, save, replace]);

  const discardDraft = useCallback(async () => {
    setActionError(null);
    setDiscarding(true);
    try {
      const form = await codFormApi.forms.discardDraft(formId);
      replace({ form: { ...form, has_unpublished_changes: false } });
    } catch (err) {
      setActionError(parseError(err));
    } finally {
      setDiscarding(false);
    }
  }, [formId, replace]);

  const applyTemplate = (template) => {
    setConfig((current) => {
      const order = Array.isArray(template.blocks_order) ? template.blocks_order : [];
      const rank = (block) => {
        const index = order.indexOf(block.id);
        return index === -1 ? order.length : index;
      };
      const blocks = (current.blocks || [])
        .map((block, index) => ({ block, index }))
        .sort((a, b) => rank(a.block) - rank(b.block) || a.index - b.index)
        .map((entry) => entry.block);
      const submit = blocks.filter((block) => block.type === "submit");
      return {
        ...current,
        design: { ...(current.design || {}), ...(template.design || {}), header: { ...((current.design || {}).header || {}), ...((template.design || {}).header || {}) } },
        blocks: [...blocks.filter((block) => block.type !== "submit"), ...submit],
      };
    });
    setData((current) => ({ ...current, form: { ...current.form, template_key: template.key } }));
    setTemplatesOpen(false);
  };

  const tabs = [
    { id: "fields", content: t("designer.tab_fields", "Fields") },
    { id: "blocks", content: t("designer.tab_blocks", "Blocks") },
    { id: "design", content: t("designer.tab_design", "Design") },
    { id: "texts", content: t("designer.tab_texts", "Texts") },
    { id: "thank_you", content: t("designer.tab_thank_you", "Thank-you") },
    { id: "form", content: t("designer.tab_form", "Form") },
  ];
  const previewView = tabs[tab].id === "thank_you" ? "thankyou" : undefined;
  const warnings = (data && data.warnings) || [];
  const describe = (entry) => (typeof entry === "string" ? entry : entry.message || JSON.stringify(entry));
  const publishErrors = (() => {
    const raw = data && data.publishErrors;
    if (Array.isArray(raw)) return raw.map(describe);
    if (raw && typeof raw === "object") {
      return Object.keys(raw).reduce((all, key) => all.concat([].concat(raw[key]).map((message) => `${key}: ${describe(message)}`)), []);
    }
    return [];
  })();

  return (
    <Screen
      title={data && data.form.name ? data.form.name : t("designer.title", "Form designer")}
      subtitle={t("designer.subtitle", "Choose the fields, look and texts of your COD Form.")}
      backPath={showFormsLink ? PATHS.forms : undefined}
      backLabel={t("designer.forms_title", "Forms")}
      secondaryActions={
        showFormsLink
          ? undefined
          : [{ content: t("designer.manage_forms", "All forms"), onAction: () => navigateTo(PATHS.forms) }]
      }
      loading={loading || !data || !defaults}
      error={error}
      onRetry={reload}
    >
      {data && defaults && (
        <>
          <ScreenSaveBar
            open={isDirty}
            saving={saving}
            onSave={save}
            onDiscard={discard}
          />
          <SaveErrorBanner error={saveError || actionError} onDismiss={() => { clearSaveError(); setActionError(null); }} />
          {warnings.length > 0 && (
            <Banner tone="warning" title={t("designer.warnings_title", "Saved, with notes")}>
              <List type="bullet">
                {warnings.slice(0, 6).map((warning, index) => (
                  <List.Item key={index}>{describe(warning)}</List.Item>
                ))}
              </List>
            </Banner>
          )}
          {publishErrors.length > 0 && (
            <Banner tone="critical" title={t("designer.publish_errors_title", "Fix these before you publish")}>
              <List type="bullet">
                {publishErrors.slice(0, 8).map((message, index) => (
                  <List.Item key={index}>{message}</List.Item>
                ))}
              </List>
            </Banner>
          )}
          <InlineGrid columns={{ xs: 1, lg: "3fr 2fr" }} gap="400" alignItems="start">
            <BlockStack gap="400">
              <Card padding="200">
                <Tabs tabs={tabs} selected={tab} onSelect={setTab} />
              </Card>
              {tabs[tab].id === "fields" && (
                <FieldsTab config={config} setConfig={setConfig} defaultsTexts={defaultsTexts} locale={locale} />
              )}
              {tabs[tab].id === "blocks" && <BlocksTab config={config} setConfig={setConfig} locale={locale} />}
              {tabs[tab].id === "design" && (
                <DesignTab config={config} setConfig={setConfig} onOpenTemplates={() => setTemplatesOpen(true)} />
              )}
              {tabs[tab].id === "texts" && (
                <TextsTab
                  config={config}
                  setConfig={setConfig}
                  defaultsTexts={defaultsTexts}
                  locale={locale}
                  locales={locales}
                  onLocaleChange={setLocale}
                />
              )}
              {tabs[tab].id === "thank_you" && <ThankYouTab config={config} setConfig={setConfig} locale={locale} />}
              {tabs[tab].id === "form" && (
                <FormTargetingCard
                  name={data.form.name}
                  targeting={data.form.targeting}
                  isDefault={!!data.form.is_default}
                  onNameChange={(name) => setData((current) => ({ ...current, form: { ...current.form, name } }))}
                  onTargetingChange={(targeting) => setData((current) => ({ ...current, form: { ...current.form, targeting } }))}
                />
              )}
            </BlockStack>
            <StickyColumn>
              <DevicePreview
                key={previewView || "form"}
                initialView={previewView || "form"}
                config={config}
                defaultsTexts={defaultsTexts}
                locale={locale}
                locales={locales}
                onLocaleChange={setLocale}
                bootstrap={bootstrap}
              />
            </StickyColumn>
          </InlineGrid>
          <TemplatesModal
            open={templatesOpen}
            templates={defaults.templates}
            onClose={() => setTemplatesOpen(false)}
            onApply={applyTemplate}
          />
        </>
      )}
    </Screen>
  );
};

export default DesignerPage;
