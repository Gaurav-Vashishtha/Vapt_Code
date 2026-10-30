import React, { useMemo, useState } from "react";
import {
  Modal,
  BlockStack,
  Box,
  TextField,
  Button,
  Banner,
  Text,
  Link,
  InlineStack,
  Divider,
} from "@shopify/polaris";
import useApi from "../../Hooks/useApi";
import WhatsappErrorBanner from "../../Components/WhatsappErrorBanner";
import { navigateToPreservingParams } from "../../../utils/navigate";

import I18n from "../../i18n-lang";
// Per-event-type copy. Keeps the UI clear about WHAT the optional source ID
// is pointing at — a "checkout token" for abandoned_cart vs. an "order ID"
// for the order-driven triggers.
const EVENT_COPY = {
  order_created: {
    get title() {
      return I18n.t("test_automation_modal.test_order_created");
    },
    idLabel: "Shopify order ID (optional)",
    idHelp:
      "Provide a past order to render the template with real customer data. Leave blank to use sample placeholders.",
    idPlaceholder: "e.g. 7392461979932",
  },
  order_fulfilled: {
    get title() {
      return I18n.t("test_automation_modal.test_order_fulfilled");
    },
    idLabel: "Shopify order ID (optional)",
    idHelp:
      "A shipped order will pull tracking info into the message. Leave blank to use sample placeholders.",
    idPlaceholder: "e.g. 7392461979932",
  },
  first_time_purchase: {
    get title() {
      return I18n.t("test_automation_modal.test_first_time_purchase");
    },
    idLabel: "Shopify order ID (optional)",
    idHelp:
      "Provide any past order to render with real data. In production this fires only on the customer's first ever order.",
    idPlaceholder: "e.g. 7392461979932",
  },
  cod_verification_reminder: {
    title: "Test COD verification reminder",
    idLabel: "Shopify order ID (optional)",
    idHelp:
      "Provide a COD order to render with real data. In production this is skipped once the order is confirmed or cancelled.",
    idPlaceholder: "e.g. 7392461979932",
  },
  order_cancelled: {
    title: "Test order cancelled",
    idLabel: "Shopify order ID (optional)",
    idHelp:
      "Provide a cancelled order to render with real data. Leave blank to use sample placeholders.",
    idPlaceholder: "e.g. 7392461979932",
  },
  order_out_for_delivery: {
    title: "Test out for delivery",
    idLabel: "Shopify order ID (optional)",
    idHelp:
      "A shipped order will pull tracking info into the message. Leave blank to use sample placeholders.",
    idPlaceholder: "e.g. 7392461979932",
  },
  order_delivered: {
    title: "Test order delivered",
    idLabel: "Shopify order ID (optional)",
    idHelp:
      "A shipped order will pull tracking info into the message. Leave blank to use sample placeholders.",
    idPlaceholder: "e.g. 7392461979932",
  },
  feedback_request: {
    title: "Test feedback request",
    idLabel: "Shopify order ID (optional)",
    idHelp:
      "Provide any past order to render with real data. Leave blank to use sample placeholders.",
    idPlaceholder: "e.g. 7392461979932",
  },
  reorder_reminder: {
    title: "Test reorder reminder",
    idLabel: "Shopify order ID (optional)",
    idHelp:
      "Provide any past order to render with real data. Leave blank to use sample placeholders.",
    idPlaceholder: "e.g. 7392461979932",
  },
  abandoned_cart: {
    get title() {
      return I18n.t("test_automation_modal.test_abandoned_cart");
    },
    idLabel: "Shopify checkout token (optional)",
    idHelp:
      "Use a checkout token from Shopify Admin → Orders → Drafts/Abandoned. Leave blank to use sample placeholders.",
    idPlaceholder: "checkout token",
  },
};

// Fill {{N}} placeholders in `text` with the supplied values (positional).
// Mirrors what the merchant will see on WhatsApp before send time.
const renderBody = (text, sampleByPosition) =>
  (text || "").replace(/\{\{(\d+)\}\}/g, (_m, n) => {
    const v = sampleByPosition[n];
    return v == null ? `{{${n}}}` : String(v);
  });

const TemplatePreview = ({ template, event }) => {
  const bodyComp = (template?.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "BODY"
  );
  const footerComp = (template?.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "FOOTER"
  );
  const headerComp = (template?.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "HEADER"
  );
  const buttonsComp = (template?.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "BUTTONS"
  );

  // position → sample value, derived from the template's variable_mapping
  // and the event's variable samples. This is exactly what the send will
  // render with when order ID is blank.
  const samples = useMemo(() => {
    const out = {};
    const mapping = template?.variableMapping || {};
    const varByKey = {};
    (event?.variables || []).forEach((v) => {
      varByKey[v.key] = v;
    });
    Object.entries(mapping).forEach(([pos, key]) => {
      out[pos] = varByKey[key]?.sample ?? `{{${pos}}}`;
    });
    return out;
  }, [template, event]);

  const rendered = renderBody(bodyComp?.text, samples);

  return (
    <Box
      padding="200"
      borderColor="border"
      borderWidth="025"
      borderRadius="200"
      background="bg-surface-secondary"
    >
      <div
        style={{
          background: "#e5ddd5",
          borderRadius: 8,
          padding: 10,
          fontFamily: "system-ui, -apple-system, sans-serif",
        }}
      >
        <div
          style={{
            background: "#ffffff",
            borderRadius: 6,
            padding: "8px 10px",
            fontSize: 13,
            lineHeight: 1.4,
            color: "#111b21",
          }}
        >
          {headerComp && headerComp.format === "TEXT" && (
            <div style={{ fontWeight: 700, marginBottom: 6 }}>
              {headerComp.text}
            </div>
          )}
          {headerComp &&
            ["IMAGE", "VIDEO", "DOCUMENT"].includes(headerComp.format) && (
              <div
                style={{
                  background: "#d9d9d9",
                  color: "#5e5e5e",
                  fontSize: 11,
                  textAlign: "center",
                  padding: "26px 8px",
                  borderRadius: 4,
                  marginBottom: 6,
                }}
              >
                {headerComp.format === "IMAGE"
                  ? "🖼 Image header"
                  : headerComp.format === "VIDEO"
                  ? "🎬 Video header"
                  : "📄 Document header"}
              </div>
            )}
          {bodyComp && (
            <div>
              {rendered.split("\n").map((line, i) => (
                <div key={i}>{line || " "}</div>
              ))}
            </div>
          )}
          {footerComp && (
            <div style={{ marginTop: 6, fontSize: 11, color: "#667781" }}>
              {footerComp.text}
            </div>
          )}
          <div
            style={{
              fontSize: 10,
              color: "#8696a0",
              textAlign: "right",
              marginTop: 4,
            }}
          >
            {I18n.t("test_automation_modal.12_34_pm")}
          </div>
        </div>
        {(buttonsComp?.buttons || []).map((b, idx) => (
          <div
            key={idx}
            style={{
              marginTop: 6,
              background: "#ffffff",
              borderRadius: 6,
              padding: "8px 10px",
              fontSize: 13,
              color: "#027eb5",
              textAlign: "center",
              fontWeight: 500,
            }}
          >
            {b.type === "URL" ? "↗" : b.type === "PHONE_NUMBER" ? "📞" : "↩"}{" "}
            {b.text || "Button"}
          </div>
        ))}
      </div>
    </Box>
  );
};

const TestAutomationModal = ({
  open,
  eventTypeKey,
  stageIndex = 0,
  binding,
  template,
  event,
  onClose,
}) => {
  const [recipientPhone, setRecipientPhone] = useState("");
  const [orderId, setOrderId] = useState("");
  const [showOrderId, setShowOrderId] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState(null);
  const [errorBanner, setErrorBanner] = useState(null);

  const [, postTest] = useApi(
    { url: "/api/whatsapp/automation_tests", method: "POST" },
    { manual: true }
  );

  const reset = () => {
    setRecipientPhone("");
    setOrderId("");
    setShowOrderId(false);
    setSubmitting(false);
    setResult(null);
    setErrorBanner(null);
  };

  const handleClose = () => {
    reset();
    onClose?.();
  };

  // Navigate to the Activity (logs) page within the embedded app. A plain link
  // to the app's own URL breaks out of the Shopify admin iframe and lands on
  // the login page; this uses App Bridge v4 navigation (pushState + popstate)
  // and preserves the host/shop params so the embedded session is kept.
  const openActivity = (logId) => {
    handleClose();
    navigateToPreservingParams("/features/whatsapp/logs", { log_id: logId });
  };

  const handleSubmit = async () => {
    setErrorBanner(null);
    setResult(null);

    if (!recipientPhone.trim()) {
      setErrorBanner({
        message: "Enter the phone number you want to receive this test.",
      });
      return;
    }

    setSubmitting(true);
    try {
      const { data } = await postTest({
        data: {
          event_type_key: eventTypeKey,
          stage_index: stageIndex,
          order_id: orderId.trim() || undefined,
          recipient_override: recipientPhone.trim(),
        },
      });
      setResult(data);
    } catch (err) {
      const code = err?.response?.data?.error_code;
      const msg = err?.response?.data?.error || err?.message;
      setErrorBanner({ code, message: msg || "Test failed" });
    } finally {
      setSubmitting(false);
    }
  };

  if (!eventTypeKey) return null;
  const copy = EVENT_COPY[eventTypeKey] || EVENT_COPY.order_created;

  const sentOk = result?.ok && result?.status !== "failed";

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title={copy.title}
      large
      primaryAction={{
        content: result ? "Send another" : "Send test now",
        onAction: result ? () => setResult(null) : handleSubmit,
        loading: submitting,
        disabled: submitting,
      }}
      secondaryActions={[{ content: I18n.t("test_automation_modal.close"), onAction: handleClose }]}
    >
      <Modal.Section>
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)",
            gap: 20,
          }}
        >
          {/* Left: form */}
          <BlockStack gap="400">
            <Text as="p" tone="subdued">
              {I18n.t("test_automation_modal.fires_the_bound_template")} <strong>{binding?.templateName}</strong> {I18n.t("test_automation_modal.as_a_real_whatsapp_message_use")}
            </Text>

            {errorBanner && (
              <WhatsappErrorBanner
                code={errorBanner.code}
                rawMessage={errorBanner.message}
                onDismiss={() => setErrorBanner(null)}
              />
            )}

            {result && (
              <Banner
                tone={sentOk ? "success" : "critical"}
                onDismiss={() => setResult(null)}
              >
                {sentOk ? (
                  <BlockStack gap="100">
                    <Text as="p">
                      {I18n.t("test_automation_modal.sent_to_using_status", {
                        recipient: result.recipient,
                        template: result.templateName,
                        status: result.status,
                      })}
                    </Text>
                    <Link onClick={() => openActivity(result.logId)}>
                      {I18n.t("test_automation_modal.view_in_activity")}
                    </Link>
                  </BlockStack>
                ) : (
                  <BlockStack gap="100">
                    <Text as="p">
                      {I18n.t("test_automation_modal.delivered_with_errors", {
                        error:
                          result.errorMessage ||
                          I18n.t("test_automation_modal.error_code", {
                            code: result.errorCode,
                          }),
                      })}
                    </Text>
                    <Link onClick={() => openActivity(result.logId)}>
                      {I18n.t("test_automation_modal.view_in_activity")}
                    </Link>
                  </BlockStack>
                )}
              </Banner>
            )}

            {!result && (
              <>
                <TextField
                  label={I18n.t("test_automation_modal.send_to")}
                  value={recipientPhone}
                  onChange={setRecipientPhone}
                  placeholder="+919999988888"
                  autoComplete="off"
                  requiredIndicator
                  helpText={I18n.t("test_automation_modal.include_country_code_if_your_waba")}
                />

                {/* No real-source field for abandoned_cart (ephemeral; Checkout
                    API unreliable) or first_time_purchase (an arbitrary past
                    order isn't really a "first" order, so it's misleading) —
                    those test with sample values + the recipient above. The
                    plain order events keep the optional "render with a real
                    order" path. */}
                {!["abandoned_cart", "first_time_purchase"].includes(eventTypeKey) && (
                  <>
                    <Divider />

                    <Box>
                      <Button
                        variant="plain"
                        disclosure={showOrderId ? "up" : "down"}
                        onClick={() => setShowOrderId((v) => !v)}
                      >
                        {I18n.t("test_automation_modal.optional_render_with_a_real_shopify")}
                      </Button>
                    </Box>

                    {showOrderId && (
                      <Box paddingInlineStart="400">
                        <TextField
                          label={copy.idLabel}
                          value={orderId}
                          onChange={setOrderId}
                          placeholder={copy.idPlaceholder}
                          helpText={copy.idHelp}
                          autoComplete="off"
                        />
                      </Box>
                    )}
                  </>
                )}
              </>
            )}
          </BlockStack>

          {/* Right: preview */}
          <BlockStack gap="200">
            <InlineStack gap="100" blockAlign="center">
              <Text as="h3" variant="headingSm">
                {I18n.t("test_automation_modal.preview")}
              </Text>
              <Text as="span" tone="subdued" variant="bodySm">
                {orderId.trim() ? "actual values render at send time" : "using sample values"}
              </Text>
            </InlineStack>
            <TemplatePreview template={template} event={event} />
          </BlockStack>
        </div>
      </Modal.Section>
    </Modal>
  );
};

export default TestAutomationModal;
