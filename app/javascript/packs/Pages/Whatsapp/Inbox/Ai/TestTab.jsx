import React, { useEffect, useRef, useState } from "react";
import {
  Badge,
  Banner,
  BlockStack,
  Box,
  Button,
  Card,
  InlineGrid,
  InlineStack,
  List,
  Text,
  TextField,
} from "@shopify/polaris";
import { DeleteMinor, RefreshMinor, SendMajor } from "@shopify/polaris-icons";
import { errorMessage, t } from "../format";
import { aiApi } from "./api";

const bubbleStyle = (mine) => ({
  maxWidth: "85%",
  padding: "8px 12px",
  borderRadius: 12,
  whiteSpace: "pre-wrap",
  overflowWrap: "anywhere",
  background: mine ? "var(--p-color-bg-fill-success-secondary, #d4f8d3)" : "var(--p-color-bg-surface-secondary, #f1f1f1)",
  alignSelf: mine ? "flex-end" : "flex-start",
});

const actionLabel = (action) => {
  const order = action.order_number || "";
  switch (action.type) {
    case "confirm_cod_order":
      return t("ai.action_confirm", "Confirms COD order %{order}", { order });
    case "cancel_cod_order":
      return t("ai.action_cancel", "Cancels order %{order}", { order });
    case "send_payment_link":
      return t("ai.action_paylink", "Sends payment link for %{order}", { order });
    case "search_products":
      return t("ai.action_search", "Searched products: %{query}", { query: action.query || "" });
    case "place_cod_order":
      return action.ok
        ? t("ai.action_place_order", "Places COD order %{order}", { order: action.order_number || "" })
        : t("ai.action_place_order_failed", "Order not placed");
    case "get_discount_code":
      return action.ok
        ? t("ai.action_discount", "Gives discount %{code}", { code: action.code || "" })
        : t("ai.action_discount_denied", "Discount not allowed");
    default:
      return action.type;
  }
};

const REASONS = {
  cancel_request: () => t("ai.reason_cancel", "Cancel request"),
  return_refund: () => t("ai.reason_return", "Return or refund"),
  address_change: () => t("ai.reason_address", "Address change"),
  complaint: () => t("ai.reason_complaint", "Complaint"),
  human_requested: () => t("ai.reason_human", "Asked for a person"),
  media: () => t("ai.reason_media", "Photo or voice note"),
  payment_issue: () => t("ai.reason_payment", "Payment issue"),
  unsure: () => t("ai.reason_unsure", "Not sure"),
  daily_limit: () => t("ai.reason_daily_limit", "Daily AI limit reached"),
  other: () => t("ai.reason_other", "Other"),
};

export const reasonLabel = (reason) => (REASONS[reason] || REASONS.other)();

const Playground = ({ form }) => {
  const [phone, setPhone] = useState("");
  const [draft, setDraft] = useState("");
  const [chat, setChat] = useState([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const endRef = useRef(null);

  useEffect(() => {
    if (endRef.current) endRef.current.scrollTop = endRef.current.scrollHeight;
  }, [chat, busy]);

  const send = async () => {
    const text = draft.trim();
    if (!text || busy) return;
    const next = [...chat, { role: "customer", text }];
    setChat(next);
    setDraft("");
    setBusy(true);
    setError(null);
    try {
      const data = await aiApi.playground({
        messages: next.map(({ role, text: body }) => ({ role, text: body })),
        phone,
        settings: form,
      });
      if (data.error) setError(data.error);
      setChat((prev) => [
        ...prev,
        {
          role: "store",
          text: data.reply || t("ai.no_reply", "(no reply)"),
          kind: data.kind,
          intent: data.intent,
          reason: data.handoff_reason,
          note: data.note,
          actions: data.actions || [],
        },
      ]);
    } catch (e) {
      setChat(chat);
      setDraft(text);
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card>
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center">
          <Text as="h3" variant="headingSm">
            {t("ai.playground_title", "Try it here")}
          </Text>
          <Button icon={RefreshMinor} variant="tertiary" onClick={() => setChat([])} disabled={busy || !chat.length}>
            {t("ai.reset_chat", "Reset")}
          </Button>
        </InlineStack>
        <Text as="p" tone="subdued">
          {t(
            "ai.playground_body",
            "Chat as a customer. Uses your unsaved settings. Nothing is sent and no order is changed. Free, 50 tests a day.",
          )}
        </Text>
        <TextField
          label={t("ai.act_as", "Act as customer (optional)")}
          value={phone}
          onChange={setPhone}
          placeholder="919876543210"
          helpText={t(
            "ai.act_as_help",
            "Without a number the AI sees no orders. Use a number that has orders or got an abandoned-cart message.",
          )}
          autoComplete="off"
        />
        <div
          ref={endRef}
          style={{
            height: 340,
            overflowY: "auto",
            display: "flex",
            flexDirection: "column",
            gap: 8,
            padding: 12,
            borderRadius: 12,
            border: "1px solid var(--p-color-border-secondary, #ebebeb)",
          }}
        >
          {chat.length === 0 && (
            <Text as="p" tone="subdued" alignment="center">
              {t("ai.playground_empty", "Try \"Where is my order?\", \"Is this available in M?\" or \"haan confirm kar do\".")}
            </Text>
          )}
          {chat.map((item, index) => (
            <div key={index} style={{ display: "flex", flexDirection: "column" }}>
              <div style={bubbleStyle(item.role === "store")}>
                <Text as="span">{item.text}</Text>
              </div>
              {item.role === "store" && (item.kind === "handoff" || item.actions?.length > 0 || item.intent) && (
                <div style={{ alignSelf: "flex-end", marginTop: 4, maxWidth: "85%" }}>
                  <InlineStack gap="100" align="end" wrap>
                    {item.kind === "handoff" && (
                      <Badge tone="warning">
                        {t("ai.hands_off", "Hands over: %{reason}", { reason: reasonLabel(item.reason) })}
                      </Badge>
                    )}
                    {item.actions.map((action, i) => (
                      <Badge key={i} tone={action.ok === false ? "critical" : "info"}>
                        {actionLabel(action)}
                      </Badge>
                    ))}
                    {item.kind !== "handoff" && item.intent && <Badge>{item.intent.replace(/_/g, " ")}</Badge>}
                  </InlineStack>
                  {item.note && (
                    <Text as="p" variant="bodySm" tone="subdued" alignment="end">
                      {t("ai.team_note", "Note for team: %{note}", { note: item.note })}
                    </Text>
                  )}
                </div>
              )}
            </div>
          ))}
          {busy && (
            <Text as="p" tone="subdued">
              {t("ai.typing", "AI is typing…")}
            </Text>
          )}
        </div>
        {error && (
          <Banner tone="critical" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}
        <div
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              send();
            }
          }}
        >
          <TextField
            label={t("ai.customer_message", "Customer message")}
            labelHidden
            value={draft}
            onChange={setDraft}
            placeholder={t("ai.customer_message_placeholder", "Type as the customer…")}
            autoComplete="off"
            connectedRight={
              <Button variant="primary" icon={SendMajor} onClick={send} loading={busy} disabled={!draft.trim()}>
                {t("ai.send", "Send")}
              </Button>
            }
          />
        </div>
      </BlockStack>
    </Card>
  );
};

const TestNumbers = ({ form, update, settings, onStatus }) => {
  const [value, setValue] = useState("");
  const numbers = form.test_numbers || [];
  const max = settings.limits?.max_test_numbers || 5;
  const digits = value.replace(/\D/g, "");
  const valid = digits.length >= 10 && digits.length <= 15;

  const add = () => {
    if (!valid || numbers.includes(digits) || numbers.length >= max) return;
    update({ test_numbers: [...numbers, digits] });
    setValue("");
  };

  return (
    <Card>
      <BlockStack gap="300">
        <Text as="h3" variant="headingSm">
          {t("ai.test_whatsapp_title", "Test on real WhatsApp")}
        </Text>
        <List type="number">
          <List.Item>{t("ai.test_step_1", "Add your own WhatsApp number below and save.")}</List.Item>
          <List.Item>{t("ai.test_step_2", "Switch the agent to Test at the top of this page.")}</List.Item>
          <List.Item>
            {t("ai.test_step_3", "Message your business WhatsApp number from that phone. The AI replies within seconds.")}
          </List.Item>
          <List.Item>{t("ai.test_step_4", "Happy with it? Switch to Live.")}</List.Item>
        </List>
        <Text as="p" tone="subdued" variant="bodySm">
          {t(
            "ai.test_real_note",
            "Test mode is free and acts for real: it can confirm your test orders and send payment links.",
          )}
        </Text>
        <InlineStack gap="200" blockAlign="end" wrap={false}>
          <div style={{ flex: 1 }}>
            <TextField
              label={t("ai.test_number", "Test number with country code")}
              value={value}
              onChange={setValue}
              placeholder="919876543210"
              autoComplete="off"
              disabled={numbers.length >= max}
            />
          </div>
          <Button onClick={add} disabled={!valid || numbers.length >= max}>
            {t("ai.add", "Add")}
          </Button>
        </InlineStack>
        {numbers.length > 0 ? (
          <BlockStack gap="100">
            {numbers.map((n) => (
              <Box key={n} padding="200" background="bg-surface-secondary" borderRadius="200">
                <InlineStack align="space-between" blockAlign="center">
                  <Text as="span">+{n}</Text>
                  <Button
                    icon={DeleteMinor}
                    variant="tertiary"
                    accessibilityLabel={t("ai.remove", "Remove")}
                    onClick={() => update({ test_numbers: numbers.filter((x) => x !== n) })}
                  />
                </InlineStack>
              </Box>
            ))}
          </BlockStack>
        ) : (
          <Text as="p" tone="subdued">
            {t("ai.no_test_numbers", "No test numbers yet.")}
          </Text>
        )}
        {settings.status === "off" && numbers.length > 0 && (
          <InlineStack>
            <Button onClick={() => onStatus("test")}>{t("ai.start_test", "Turn on Test mode")}</Button>
          </InlineStack>
        )}
      </BlockStack>
    </Card>
  );
};

const TestTab = ({ form, update, settings, onStatus }) => (
  <InlineGrid columns={{ xs: 1, lg: "3fr 2fr" }} gap="400" alignItems="start">
    <Playground form={form} />
    <TestNumbers form={form} update={update} settings={settings} onStatus={onStatus} />
  </InlineGrid>
);

export default TestTab;
