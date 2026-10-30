import React, { useMemo, useState } from "react";
import {
  Modal,
  BlockStack,
  InlineStack,
  Text,
  Banner,
  Divider,
  Box,
  Select,
  Badge,
  Card,
} from "@shopify/polaris";
import { TextField } from "@shopify/polaris";
import useApi from "../../Hooks/useApi";
import Api from "../../Services/Api";

import I18n from "../../i18n-lang";
// Events whose BSP send routes through DispatchEventJob and therefore honour a
// per-notification delay (binding.offset_minutes). Keep in sync with
// OFFSET_AWARE_EVENTS in WhatsappEventMappings.jsx.
const OFFSET_AWARE_EVENTS = new Set([
  "order_created",
  "order_fulfilled",
  "first_time_purchase",
  "cod_verification",
  "cod_verification_reminder",
  "order_cancelled",
  "order_out_for_delivery",
  "order_delivered",
  "feedback_request",
  "reorder_reminder",
]);

// 3-step wizard for "set up an automation":
//   Step 1: pick a trigger (event_type_key)
//   Step 2: pick a message (template), from existing approved or jump to library
//   Step 3: confirm/personalize variable mapping per {{N}} slot
//
// On finish, calls POST /api/whatsapp/template_bindings — same endpoint the
// Event Mappings tab uses today, but framed as a forward-stepping flow.

const NewAutomationWizard = ({ open, onClose, onCreated }) => {
  const [step, setStep] = useState(1);
  const [trigger, setTrigger] = useState("");
  const [templateId, setTemplateId] = useState("");
  const [mapping, setMapping] = useState({});
  const [offsetMinutes, setOffsetMinutes] = useState("0");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  // Which number this automation sends from. Empty = shop default.
  const [accountId, setAccountId] = useState("");

  const [{ data: eventsData }] = useApi(
    { url: "/api/whatsapp/events", method: "GET" },
    { manual: false }
  );
  const [{ data: accountsData }] = useApi(
    { url: "/api/whatsapp/accounts", method: "GET" },
    { manual: false }
  );
  // Templates are per-number — scope the list to the chosen number so the
  // merchant only picks templates that exist in that number's WABA.
  const [{ data: templatesData }] = useApi(
    {
      url: "/api/whatsapp/templates",
      method: "GET",
      params: accountId ? { account_id: accountId } : undefined,
    },
    { manual: false }
  );
  const [, postBinding] = useApi(
    { url: "/api/whatsapp/template_bindings", method: "POST" },
    { manual: true }
  );

  const accounts = accountsData?.accounts || [];
  // Default the number selector to the shop's default number once loaded.
  React.useEffect(() => {
    if (!accountId && accounts.length) {
      const def = accounts.find((a) => a.isDefault) || accounts[0];
      if (def) setAccountId(String(def.id));
    }
  }, [accounts, accountId]);

  // Exclude campaign broadcasts — those are sent manually, not bound as a
  // per-trigger automation.
  const events = (eventsData?.events || []).filter((e) => e.kind !== "campaign");
  const allTemplates = templatesData?.templates || [];
  const approvedForTrigger = useMemo(
    () =>
      allTemplates.filter(
        (t) => t.status === "approved" && t.eventTypeKey === trigger
      ),
    [allTemplates, trigger]
  );

  const selectedEvent = events.find((e) => e.key === trigger);
  const selectedTemplate = allTemplates.find(
    (t) => String(t.id) === String(templateId)
  );

  // Variable picker source — only the event's allow-listed variables.
  const eventVars = selectedEvent?.variables || [];

  // Pull {{N}} positions out of the chosen template's body text so the
  // personalization step can ask one question per slot.
  const positions = useMemo(() => {
    if (!selectedTemplate) return [];
    const body = (selectedTemplate.components || []).find(
      (c) => (c?.type || "").toUpperCase() === "BODY"
    );
    if (!body?.text) return [];
    const seen = new Set();
    (body.text.match(/\{\{(\d+)\}\}/g) || []).forEach((m) =>
      seen.add(m.replace(/[{}]/g, ""))
    );
    return Array.from(seen).sort((a, b) => Number(a) - Number(b));
  }, [selectedTemplate]);

  // When the template changes, seed mapping from whatever's already saved on
  // that template (preserves the merchant's earlier choices), then patch the
  // mapping state on every Select change in step 3.
  React.useEffect(() => {
    if (selectedTemplate) {
      setMapping({ ...(selectedTemplate.variableMapping || {}) });
    } else {
      setMapping({});
    }
  }, [selectedTemplate]);

  const close = () => {
    // Reset so the next open starts clean.
    setStep(1);
    setTrigger("");
    setTemplateId("");
    setMapping({});
    setOffsetMinutes("0");
    setError("");
    onClose();
  };

  const handleFinish = async () => {
    setError("");
    setSubmitting(true);
    try {
      // 1. Persist the variable mapping onto the template if changed (so the
      //    real send uses the right values).
      const token = await window.shopify?.idToken?.();
      const payloadMapping = positions.reduce((acc, p) => {
        if (mapping[p]) acc[p] = mapping[p];
        return acc;
      }, {});
      const sameMapping =
        JSON.stringify(payloadMapping) ===
        JSON.stringify(selectedTemplate?.variableMapping || {});
      if (!sameMapping) {
        await fetch(
          `https://${process.env.APP_HOST}/api/whatsapp/templates/${templateId}`,
          {
            method: "PATCH",
            headers: {
              "Content-Type": "application/json",
              ...(token ? { Authorization: `Bearer ${token}` } : {}),
            },
            body: JSON.stringify({
              event_type_key: trigger,
              variable_mapping: payloadMapping,
            }),
          }
        );
      }

      // 2. Create (or replace) the binding for this trigger.
      await postBinding({
        data: {
          event_type_key: trigger,
          whatsapp_template_id: Number(templateId),
          ...(accountId ? { whatsapp_account_id: Number(accountId) } : {}),
          ...(OFFSET_AWARE_EVENTS.has(trigger)
            ? { offset_minutes: Number(offsetMinutes) || 0 }
            : {}),
        },
      });

      onCreated?.({ trigger, templateId });
      close();
    } catch (err) {
      setError(
        err?.response?.data?.error ||
          err?.message ||
          "Couldn't activate the automation. Try again."
      );
    } finally {
      setSubmitting(false);
    }
  };

  const canAdvanceFrom1 = !!trigger;
  const canAdvanceFrom2 = !!templateId;
  const canFinish =
    positions.length === 0 || positions.every((p) => !!mapping[p]);

  const primary =
    step === 1
      ? { content: I18n.t("new_automation_wizard.next"), onAction: () => setStep(2), disabled: !canAdvanceFrom1 }
      : step === 2
      ? { content: I18n.t("new_automation_wizard.next"), onAction: () => setStep(3), disabled: !canAdvanceFrom2 }
      : {
          content: I18n.t("new_automation_wizard.activate_automation"),
          onAction: handleFinish,
          loading: submitting,
          disabled: !canFinish,
        };

  const secondary =
    step === 1
      ? [{ content: I18n.t("new_automation_wizard.cancel"), onAction: close }]
      : [
          { content: I18n.t("new_automation_wizard.back"), onAction: () => setStep(step - 1) },
          { content: I18n.t("new_automation_wizard.cancel"), onAction: close },
        ];

  return (
    <Modal
      open={open}
      onClose={close}
      title={`New automation · Step ${step} of 3`}
      primaryAction={primary}
      secondaryActions={secondary}
      large
    >
      <Modal.Section>
        <BlockStack gap="400">
          {error && <Banner tone="critical">{error}</Banner>}

          {step === 1 && (
            <BlockStack gap="300">
              <Text as="h3" variant="headingMd">
                {I18n.t("new_automation_wizard.what_should_trigger_this_message")}
              </Text>
              <Text as="p" tone="subdued">
                {I18n.t("new_automation_wizard.pick_a_customer_moment_the_message")}
              </Text>
              <BlockStack gap="200">
                {events.map((e) => (
                  <TriggerCard
                    key={e.key}
                    event={e}
                    selected={trigger === e.key}
                    onSelect={() => setTrigger(e.key)}
                  />
                ))}
              </BlockStack>
            </BlockStack>
          )}

          {step === 2 && (
            <BlockStack gap="300">
              <Text as="h3" variant="headingMd">
                {I18n.t("new_automation_wizard.which_template_to_send")}
              </Text>
              <Text as="p" tone="subdued">
                {I18n.t("new_automation_wizard.only_approved_templates_listed", {
                  event: selectedEvent?.label ?? "",
                })}
              </Text>
              {accounts.length > 1 && (
                <Select
                  label={I18n.t("new_automation_wizard.send_from_number")}
                  helpText={I18n.t("new_automation_wizard.this_automation_will_send_from_the")}
                  options={accounts.map((a) => ({
                    label: `${a.displayLabel || a.displayPhoneNumber || "Number"}${a.isDefault ? " (default)" : ""}`,
                    value: String(a.id),
                  }))}
                  value={accountId}
                  onChange={(v) => {
                    setAccountId(v);
                    // Templates are number-scoped, so the old selection may not
                    // exist on the new number.
                    setTemplateId("");
                  }}
                />
              )}
              {approvedForTrigger.length === 0 ? (
                <Banner tone="warning">
                  {I18n.t("new_automation_wizard.no_approved_templates_for_this_trigger")}
                </Banner>
              ) : (
                <BlockStack gap="200">
                  {approvedForTrigger.map((t) => (
                    <MessageCard
                      key={t.id}
                      template={t}
                      selected={String(templateId) === String(t.id)}
                      onSelect={() => setTemplateId(String(t.id))}
                    />
                  ))}
                </BlockStack>
              )}
            </BlockStack>
          )}

          {step === 3 && (
            <BlockStack gap="300">
              <Text as="h3" variant="headingMd">
                {I18n.t("new_automation_wizard.fill_in_personalization")}
              </Text>
              <Text as="p" tone="subdued">
                {I18n.t("new_automation_wizard.for_each_placeholder_in_the_template")}
              </Text>
              {positions.length === 0 ? (
                <Banner tone="success">
                  {I18n.t("new_automation_wizard.this_template_has_no_personalization_ready")}
                </Banner>
              ) : (
                positions.map((p) => (
                  <Select
                    key={p}
                    label={`{{${p}}}`}
                    options={[
                      { label: I18n.t("new_automation_wizard.choose_a_field"), value: "" },
                      ...eventVars.map((v) => ({ label: v.label, value: v.key })),
                    ]}
                    value={mapping[p] || ""}
                    onChange={(v) => setMapping((prev) => ({ ...prev, [p]: v }))}
                  />
                ))
              )}

              {OFFSET_AWARE_EVENTS.has(trigger) && (
                <Box maxWidth="240px">
                  <TextField
                    type="number"
                    label={I18n.t("new_automation_wizard.send_after_minutes")}
                    value={offsetMinutes}
                    onChange={setOffsetMinutes}
                    min={0}
                    autoComplete="off"
                    helpText={I18n.t("new_automation_wizard.0_send_immediately_when_the_event")}
                  />
                </Box>
              )}

              <Divider />
              <BlockStack gap="100">
                <Text tone="subdued" as="p" variant="bodySm">
                  <strong>{I18n.t("new_automation_wizard.trigger")}</strong> {selectedEvent?.label}
                </Text>
                <Text tone="subdued" as="p" variant="bodySm">
                  <strong>{I18n.t("new_automation_wizard.template")}</strong> {selectedTemplate?.name}
                </Text>
              </BlockStack>
            </BlockStack>
          )}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

const TriggerCard = ({ event, selected, onSelect }) => (
  <Card
    background={selected ? "bg-surface-success" : undefined}
    padding="0"
  >
    <Box
      padding="300"
      borderColor={selected ? "border-success" : "border"}
      borderWidth="025"
      borderRadius="200"
    >
      <InlineStack
        align="space-between"
        blockAlign="start"
        wrap={false}
        gap="200"
      >
        <BlockStack gap="050">
          <Text as="span" fontWeight="semibold">
            {event.label}
          </Text>
          <Text as="span" tone="subdued" variant="bodySm">
            {event.description}
          </Text>
        </BlockStack>
        <Box>
          <input
            type="radio"
            name="trigger"
            checked={selected}
            onChange={onSelect}
            style={{ transform: "scale(1.3)" }}
          />
        </Box>
      </InlineStack>
    </Box>
  </Card>
);

const MessageCard = ({ template, selected, onSelect }) => {
  const body = (template.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "BODY"
  );
  return (
    <Card padding="0">
      <Box
        padding="300"
        borderColor={selected ? "border-success" : "border"}
        borderWidth="025"
        borderRadius="200"
      >
        <InlineStack align="space-between" blockAlign="start" wrap={false} gap="200">
          <BlockStack gap="100">
            <InlineStack gap="200" blockAlign="center">
              <Text as="span" fontWeight="semibold">
                {template.name}
              </Text>
              <Badge tone="info">{template.language}</Badge>
            </InlineStack>
            <Text as="span" tone="subdued" variant="bodySm">
              {(body?.text || "").slice(0, 140)}
              {(body?.text || "").length > 140 ? "…" : ""}
            </Text>
          </BlockStack>
          <Box>
            <input
              type="radio"
              name="message"
              checked={selected}
              onChange={onSelect}
              style={{ transform: "scale(1.3)" }}
            />
          </Box>
        </InlineStack>
      </Box>
    </Card>
  );
};

export default NewAutomationWizard;
