import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  Layout,
  Card,
  BlockStack,
  Text,
  Checkbox,
  TextField,
  Select,
  Banner,
  PageActions,
  SkeletonBodyText,
} from "@shopify/polaris";
import I18n from "../../../../i18n-lang";
import { api } from "../../Campaigns/api";
import WhatsappLayout from "../../WhatsappLayout";
import BusinessHoursEditor, { hoursAreValid } from "./BusinessHoursEditor";
import KeywordRulesEditor, { VariableButtons, appendToken, ruleErrors } from "./KeywordRulesEditor";
import SavedRepliesManager from "./SavedRepliesManager";
import LabelsManager from "./LabelsManager";

const t = (key, defaultValue, opts = {}) =>
  I18n.t(`whatsapp_inbox_settings.${key}`, { defaultValue, ...opts });

const SETTINGS_PATH = "/api/whatsapp/inbox/settings";
const INBOX_PATH = "/features/whatsapp/inbox";
const MAX_TEXT_LENGTH = 1024;

const toForm = (settings) => ({
  read_receipts: Boolean(settings.read_receipts),
  auto_label: Boolean(settings.auto_label),
  welcome: { enabled: Boolean(settings.welcome?.enabled), text: settings.welcome?.text || "" },
  away: {
    enabled: Boolean(settings.away?.enabled),
    text: settings.away?.text || "",
    hours: settings.away?.hours || {},
  },
  keyword_rules: settings.keyword_rules || [],
  unanswered_email: {
    enabled: Boolean(settings.unanswered_email?.enabled),
    minutes: settings.unanswered_email?.minutes || 30,
  },
});

const showToast = (message) => {
  if (typeof shopify !== "undefined" && shopify.toast) shopify.toast.show(message);
};

const InboxSettingsPage = () => {
  const [settings, setSettings] = useState(null);
  const [form, setForm] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [saveError, setSaveError] = useState(null);
  const [saving, setSaving] = useState(false);
  const [showErrors, setShowErrors] = useState(false);

  const load = useCallback(async () => {
    setLoadError(null);
    try {
      const data = await api(SETTINGS_PATH);
      setSettings(data.settings);
      setForm(toForm(data.settings));
    } catch (e) {
      setLoadError(e.message);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const dirty = useMemo(
    () => Boolean(settings && form && JSON.stringify(toForm(settings)) !== JSON.stringify(form)),
    [settings, form]
  );

  const errors = useMemo(() => {
    if (!form) return {};
    const result = {};
    if (form.welcome.enabled && !form.welcome.text.trim()) {
      result.welcome = t("welcome.text_required", "Write the welcome message or turn it off");
    }
    if (form.away.enabled && !form.away.text.trim()) {
      result.away = t("away.text_required", "Write the away message or turn it off");
    }
    if (!hoursAreValid(form.away.hours)) {
      result.hours = t("hours.close_after_open", "Must be after opening time");
    }
    if (form.keyword_rules.some((rule) => Object.keys(ruleErrors(rule)).length > 0)) {
      result.keyword_rules = true;
    }
    return result;
  }, [form]);

  const set = (path, value) =>
    setForm((current) => {
      const [section, key] = path.split(".");
      if (!key) return { ...current, [section]: value };
      return { ...current, [section]: { ...current[section], [key]: value } };
    });

  const save = async () => {
    if (Object.keys(errors).length > 0) {
      setShowErrors(true);
      setSaveError(t("fix_errors", "Fix the highlighted fields, then save again."));
      return;
    }
    setSaving(true);
    setSaveError(null);
    try {
      const data = await api(SETTINGS_PATH, { method: "PATCH", body: form });
      setSettings(data.settings);
      setForm(toForm(data.settings));
      setShowErrors(false);
      showToast(t("saved", "Settings saved"));
    } catch (e) {
      setSaveError(e.message);
    } finally {
      setSaving(false);
    }
  };

  const variables = settings?.variables;
  const saveAction = {
    content: t("save", "Save"),
    onAction: save,
    loading: saving,
    disabled: !dirty,
  };

  return (
    <WhatsappLayout
      title={t("title", "Inbox settings")}
      backTo={INBOX_PATH}
      backLabel={t("back", "Inbox")}
      primaryAction={form ? saveAction : undefined}
    >
      <Layout>
        {loadError && (
          <Layout.Section>
            <Banner
              tone="critical"
              title={t("load_failed", "Couldn't load inbox settings")}
              action={{ content: t("retry", "Try again"), onAction: load }}
            >
              {loadError}
            </Banner>
          </Layout.Section>
        )}
        {saveError && (
          <Layout.Section>
            <Banner tone="critical" onDismiss={() => setSaveError(null)}>
              {saveError}
            </Banner>
          </Layout.Section>
        )}

        {!form && !loadError && (
          <Layout.Section>
            <Card>
              <SkeletonBodyText lines={6} />
            </Card>
          </Layout.Section>
        )}

        {form && (
          <>
            <Layout.AnnotatedSection
              title={t("general.title", "General")}
              description={t("general.description", "How the inbox behaves for every conversation.")}
            >
              <Card>
                <BlockStack gap="300">
                  <Checkbox
                    label={t("read_receipts.label", "Send read receipts")}
                    helpText={t(
                      "read_receipts.help",
                      "Customers see blue ticks when someone on your team opens their conversation."
                    )}
                    checked={form.read_receipts}
                    onChange={(value) => set("read_receipts", value)}
                  />
                  <Checkbox
                    label={t("auto_label.label", "Label conversations automatically")}
                    helpText={t(
                      "auto_label.help",
                      "Adds Campaign reply, Notification reply and Cancel request labels based on what the customer replied to or wrote."
                    )}
                    checked={form.auto_label}
                    onChange={(value) => set("auto_label", value)}
                  />
                </BlockStack>
              </Card>
            </Layout.AnnotatedSection>

            <Layout.AnnotatedSection
              title={t("welcome.label", "Welcome message")}
              description={t(
                "welcome.help",
                "Sent automatically the first time a customer messages you. Not sent if your team replied in the last 6 hours."
              )}
            >
              <Card>
                <BlockStack gap="300">
                  <Checkbox
                    label={t("welcome.enable", "Send a welcome message")}
                    checked={form.welcome.enabled}
                    onChange={(value) => set("welcome.enabled", value)}
                  />
                  <TextField
                    label={t("welcome.text", "Message")}
                    value={form.welcome.text}
                    onChange={(value) => set("welcome.text", value)}
                    multiline={3}
                    maxLength={MAX_TEXT_LENGTH}
                    showCharacterCount
                    autoComplete="off"
                    disabled={!form.welcome.enabled}
                    error={showErrors ? errors.welcome : undefined}
                  />
                  {form.welcome.enabled && (
                    <VariableButtons
                      variables={variables}
                      onInsert={(token) => set("welcome.text", appendToken(form.welcome.text, token))}
                    />
                  )}
                </BlockStack>
              </Card>
            </Layout.AnnotatedSection>

            <Layout.AnnotatedSection
              title={t("away.label", "Away message")}
              description={t(
                "away.help",
                "Sent automatically when a customer writes outside your business hours. At most one automatic reply every 6 hours per customer."
              )}
            >
              <Card>
                <BlockStack gap="300">
                  <Checkbox
                    label={t("away.enable", "Send an away message")}
                    checked={form.away.enabled}
                    onChange={(value) => set("away.enabled", value)}
                  />
                  <TextField
                    label={t("away.text", "Message")}
                    value={form.away.text}
                    onChange={(value) => set("away.text", value)}
                    multiline={3}
                    maxLength={MAX_TEXT_LENGTH}
                    showCharacterCount
                    autoComplete="off"
                    disabled={!form.away.enabled}
                    error={showErrors ? errors.away : undefined}
                  />
                  {form.away.enabled && (
                    <VariableButtons
                      variables={variables}
                      onInsert={(token) => set("away.text", appendToken(form.away.text, token))}
                    />
                  )}
                  {form.away.enabled && Object.keys(form.away.hours || {}).length === 0 && (
                    <Banner tone="info">
                      {t(
                        "away.no_hours",
                        "You're set to open all the time, so the away message won't be sent. Set business hours below."
                      )}
                    </Banner>
                  )}
                </BlockStack>
              </Card>
            </Layout.AnnotatedSection>

            <Layout.AnnotatedSection
              title={t("away.hours", "Business hours")}
              description={t(
                "hours.help",
                "Used for the away message and for unanswered conversation emails."
              )}
            >
              <Card>
                <BlockStack gap="200">
                  <BusinessHoursEditor
                    hours={form.away.hours}
                    timezone={settings?.away?.timezone}
                    onChange={(hours) => set("away.hours", hours)}
                  />
                  {showErrors && errors.hours && (
                    <Text as="p" tone="critical">
                      {errors.hours}
                    </Text>
                  )}
                </BlockStack>
              </Card>
            </Layout.AnnotatedSection>

            <Layout.AnnotatedSection
              title={t("keyword_rules.title", "Keyword replies")}
              description={t(
                "keyword_rules.help",
                "Reply automatically when a message has a keyword. Keyword replies are checked first, then the away message, then the welcome message."
              )}
            >
              <Card>
                <KeywordRulesEditor
                  rules={form.keyword_rules}
                  variables={variables}
                  showErrors={showErrors}
                  onChange={(rules) => set("keyword_rules", rules)}
                />
              </Card>
            </Layout.AnnotatedSection>

            <Layout.AnnotatedSection
              title={t("unanswered_email.label", "Unanswered conversation email")}
              description={t(
                "unanswered_email.help",
                "Email the assigned teammate, or the store owner if nobody is assigned, when a customer waits too long during business hours."
              )}
            >
              <Card>
                <BlockStack gap="300">
                  <Checkbox
                    label={t("unanswered_email.enable", "Send an email when a customer is waiting")}
                    checked={form.unanswered_email.enabled}
                    onChange={(value) => set("unanswered_email.enabled", value)}
                  />
                  <Select
                    label={t("unanswered_email.minutes", "Send after")}
                    options={[15, 30, 60].map((m) => ({
                      label: t("unanswered_email.minutes_option", "%{count} minutes without a reply", { count: m }),
                      value: String(m),
                    }))}
                    value={String(form.unanswered_email.minutes)}
                    onChange={(value) => set("unanswered_email.minutes", Number(value))}
                    disabled={!form.unanswered_email.enabled}
                  />
                </BlockStack>
              </Card>
            </Layout.AnnotatedSection>

            <Layout.AnnotatedSection
              title={t("saved_replies.title", "Saved replies")}
              description={t(
                "saved_replies.help",
                "Shared with your whole team. Type / in a reply to use one. Changes here save right away."
              )}
            >
              <Card>
                <SavedRepliesManager variables={variables} />
              </Card>
            </Layout.AnnotatedSection>

            <Layout.AnnotatedSection
              title={t("labels.title", "Labels")}
              description={t("labels.help", "Use labels to sort conversations. Changes here save right away.")}
            >
              <Card>
                <LabelsManager />
              </Card>
            </Layout.AnnotatedSection>

            <Layout.Section>
              <PageActions primaryAction={saveAction} />
            </Layout.Section>
          </>
        )}
      </Layout>
    </WhatsappLayout>
  );
};

export default InboxSettingsPage;
