import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  Badge,
  Banner,
  BlockStack,
  Box,
  Button,
  Card,
  Divider,
  InlineStack,
  Modal,
  Spinner,
  Text,
  TextField,
  Tooltip,
} from "@shopify/polaris";
import { ClipboardMinor } from "@shopify/polaris-icons";
import { inboxApi } from "./api";
import { copyText, errorMessage, formatMoney, phoneDisplay, relativeTime, t } from "./format";

const REASON_DEFAULTS = {
  not_cod: "This order isn't cash on delivery",
  not_pending: "This order is no longer waiting for payment",
  disabled: "Turn on prepaid notifications to send payment links",
  not_eligible: "Approve a WhatsApp prepaid template to send payment links",
  paused: "Prepaid messages are paused for your store",
  rate_limited: "A payment link was sent recently. Try again later",
  mismatch: "This order doesn't belong to this customer",
};

const reasonText = (code) =>
  code ? t(`customer.payment_link_reasons.${code}`, REASON_DEFAULTS[code] || code) : null;

const OrderCard = ({ order, paymentLink, onInsert, onPaymentLink }) => {
  const linkDisabledReason = !paymentLink?.available
    ? reasonText(paymentLink?.reason) || reasonText("disabled")
    : !order.payment_link_eligible
      ? reasonText("not_pending")
      : null;

  const linkButton = (
    <Button size="slim" disabled={!!linkDisabledReason} onClick={() => onPaymentLink(order)}>
      {t("customer.send_payment_link", "Send payment link")}
    </Button>
  );

  return (
    <Box padding="300" borderWidth="025" borderColor="border" borderRadius="200">
      <BlockStack gap="200">
        <InlineStack align="space-between" blockAlign="center" gap="100">
          <Text as="span" fontWeight="semibold">
            {order.order_number ? `#${String(order.order_number).replace(/^#/, "")}` : order.order_id}
          </Text>
          <Text as="span" numeric>
            {formatMoney(order.amount, order.currency)}
          </Text>
        </InlineStack>
        <InlineStack gap="100">
          <Badge tone={order.is_cod ? "attention" : "success"} size="small">
            {order.is_cod ? t("customer.cod", "COD") : t("customer.prepaid", "Prepaid")}
          </Badge>
          {order.status_label && <Badge size="small">{order.status_label}</Badge>}
          {order.shipping_status && (
            <Badge tone="info" size="small">
              {order.shipping_status}
            </Badge>
          )}
        </InlineStack>
        <Text as="span" variant="bodySm" tone="subdued">
          {relativeTime(order.created_at)}
        </Text>
        <InlineStack gap="200">
          {order.tracking_url && (
            <Button size="slim" variant="plain" onClick={() => onInsert(order.tracking_url)}>
              {t("customer.copy_tracking", "Add tracking link to reply")}
            </Button>
          )}
          {order.admin_url && (
            <Button size="slim" variant="plain" onClick={() => window.open(order.admin_url, "_top")}>
              {t("customer.open_in_shopify", "Open in Shopify")}
            </Button>
          )}
        </InlineStack>
        {order.is_cod &&
          (linkDisabledReason ? <Tooltip content={linkDisabledReason}>{linkButton}</Tooltip> : <div>{linkButton}</div>)}
      </BlockStack>
    </Box>
  );
};

const CustomerPanel = ({ conversation, onInsert, onConversationChange }) => {
  const conversationId = conversation?.id;
  const [panel, setPanel] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [note, setNote] = useState(conversation?.note || "");
  const [savingNote, setSavingNote] = useState(false);
  const [copied, setCopied] = useState(false);
  const [linkOrder, setLinkOrder] = useState(null);
  const [linkSending, setLinkSending] = useState(false);
  const [linkResult, setLinkResult] = useState(null);

  const load = useCallback(async () => {
    if (!conversationId) return;
    try {
      setPanel(await inboxApi.customer(conversationId));
      setError("");
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  }, [conversationId]);

  useEffect(() => {
    setPanel(null);
    setLoading(true);
    setLinkResult(null);
    load();
  }, [load]);

  useEffect(() => {
    setNote(conversation?.note || "");
  }, [conversationId, conversation?.note]);

  const lastMessageAt = conversation?.last_message?.at;
  const seenMessageAt = useRef(lastMessageAt);
  useEffect(() => {
    if (!lastMessageAt || lastMessageAt === seenMessageAt.current) return;
    seenMessageAt.current = lastMessageAt;
    load();
  }, [lastMessageAt, load]);

  const saveNote = async () => {
    if (!conversationId || note === (conversation?.note || "")) return;
    setSavingNote(true);
    try {
      const data = await inboxApi.updateConversation(conversationId, { note });
      if (data.conversation && onConversationChange) onConversationChange(data.conversation);
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setSavingNote(false);
    }
  };

  const copyPhone = async () => {
    const ok = await copyText(phoneDisplay(panel || conversation?.customer));
    setCopied(ok);
    if (ok) setTimeout(() => setCopied(false), 2000);
  };

  const sendLink = async () => {
    if (!linkOrder) return;
    setLinkSending(true);
    try {
      await inboxApi.sendPaymentLink(conversationId, linkOrder.id);
      setLinkResult({ tone: "success", text: t("customer.payment_link_sent", "Payment link sent on WhatsApp") });
      load();
    } catch (e) {
      setLinkResult({ tone: "critical", text: e.code ? reasonText(e.code) || errorMessage(e) : errorMessage(e) });
    } finally {
      setLinkSending(false);
      setLinkOrder(null);
    }
  };

  const insertText = (text) => onInsert && onInsert(text);

  if (loading && !panel) {
    return (
      <Card>
        <InlineStack align="center">
          <Spinner size="small" accessibilityLabel={t("customer.title", "Customer")} />
        </InlineStack>
      </Card>
    );
  }

  const name = panel?.name || conversation?.customer?.name;
  const phone = phoneDisplay(panel || conversation?.customer);
  const lifetime = panel?.lifetime || {};
  const rto = Number(panel?.rto_count || 0);
  const orders = (panel?.orders || []).slice(0, 5);
  const optedOut = panel ? panel.opted_out : conversation?.opted_out;

  return (
    <Card>
      <BlockStack gap="400">
        {error && (
          <Banner tone="critical" onDismiss={() => setError("")}>
            {error}
          </Banner>
        )}
        <BlockStack gap="100">
          <Text as="h2" variant="headingMd">
            {name || phone}
          </Text>
          <InlineStack gap="100" blockAlign="center">
            <Text as="span" tone="subdued">
              {phone}
            </Text>
            <Tooltip content={copied ? t("customer.copied", "Copied") : t("customer.copy_phone", "Copy phone number")}>
              <Button
                icon={ClipboardMinor}
                variant="tertiary"
                size="slim"
                onClick={copyPhone}
                accessibilityLabel={t("customer.copy_phone", "Copy phone number")}
              />
            </Tooltip>
          </InlineStack>
          <InlineStack gap="100">
            {optedOut ? (
              <Badge tone="warning">{t("customer.opted_out", "Unsubscribed from marketing")}</Badge>
            ) : (
              <Badge tone="success">{t("customer.opted_in", "Subscribed to marketing")}</Badge>
            )}
            {rto > 0 ? (
              <Badge tone="critical">{t("customer.rto", "RTO: %{count}", { count: rto })}</Badge>
            ) : (
              <Badge>{t("customer.no_rto", "No RTO")}</Badge>
            )}
          </InlineStack>
        </BlockStack>

        <InlineStack gap="600">
          <BlockStack gap="050">
            <Text as="span" variant="bodySm" tone="subdued">
              {t("customer.lifetime_orders", "Orders")}
            </Text>
            <Text as="span" variant="headingSm">
              {Number(lifetime.orders || 0).toLocaleString()}
            </Text>
          </BlockStack>
          <BlockStack gap="050">
            <Text as="span" variant="bodySm" tone="subdued">
              {t("customer.lifetime", "Lifetime value")}
            </Text>
            <Text as="span" variant="headingSm">
              {formatMoney(lifetime.value, lifetime.currency)}
            </Text>
          </BlockStack>
        </InlineStack>

        <Divider />

        <BlockStack gap="200">
          <Text as="h3" variant="headingSm">
            {t("customer.orders", "Recent orders")}
          </Text>
          {linkResult && (
            <Banner tone={linkResult.tone} onDismiss={() => setLinkResult(null)}>
              {linkResult.text}
            </Banner>
          )}
          {orders.length === 0 ? (
            <Text as="p" tone="subdued">
              {t("customer.no_orders", "No orders found for this number.")}
            </Text>
          ) : (
            orders.map((order) => (
              <OrderCard
                key={order.id}
                order={order}
                paymentLink={panel?.payment_link}
                onInsert={insertText}
                onPaymentLink={setLinkOrder}
              />
            ))
          )}
        </BlockStack>

        <Divider />

        <TextField
          label={t("customer.note", "Internal note")}
          helpText={savingNote ? t("customer.note_saving", "Saving…") : t("customer.note_help", "Only your team sees this.")}
          value={note}
          onChange={setNote}
          onBlur={saveNote}
          multiline={3}
          placeholder={t("customer.note_placeholder", "Add a note for your team")}
          autoComplete="off"
        />
      </BlockStack>

      <Modal
        open={!!linkOrder}
        onClose={() => setLinkOrder(null)}
        title={t("customer.send_payment_link", "Send payment link")}
        primaryAction={{ content: t("customer.send", "Send"), onAction: sendLink, loading: linkSending }}
        secondaryActions={[{ content: t("customer.cancel", "Cancel"), onAction: () => setLinkOrder(null) }]}
      >
        <Modal.Section>
          <Text as="p">
            {t(
              "customer.payment_link_confirm",
              "We'll send your prepaid payment message on WhatsApp for order %{order}.",
              { order: linkOrder?.order_number || linkOrder?.order_id || "" },
            )}
          </Text>
        </Modal.Section>
      </Modal>
    </Card>
  );
};

export default CustomerPanel;
