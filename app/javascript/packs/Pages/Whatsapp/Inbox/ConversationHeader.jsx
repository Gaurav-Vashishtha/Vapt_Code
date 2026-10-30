import React, { useState } from "react";
import { ActionList, Badge, BlockStack, Box, Button, InlineStack, Popover, Select, Text } from "@shopify/polaris";
import { ArrowLeftMinor, CustomersMajor, HorizontalDotsMinor } from "@shopify/polaris-icons";
import LabelPicker from "./LabelPicker";
import { customerName, phoneDisplay, t, windowState } from "./format";

const STATUSES = ["open", "pending", "resolved"];
const STATUS_DEFAULTS = { open: "Open", pending: "Pending", resolved: "Resolved" };

const ConversationHeader = ({
  conversation,
  agents = [],
  labels = [],
  now,
  busy,
  onUpdate,
  onLabels,
  onMarkUnread,
  onBlockToggle,
  onBack,
  onOpenCustomer,
}) => {
  const [menuOpen, setMenuOpen] = useState(false);
  const win = windowState(conversation, now);
  const name = customerName(conversation.customer);
  const phone = phoneDisplay(conversation.customer);
  const selectedLabels = (conversation.labels || []).map((l) => l.id);

  const statusOptions = STATUSES.map((s) => ({ value: s, label: t(`header.status_${s}`, STATUS_DEFAULTS[s]) }));
  const assigneeOptions = [
    { value: "", label: t("header.unassigned", "Unassigned") },
    ...agents.map((a) => ({
      value: String(a.id),
      label: a.is_me ? t("header.agent_me", "%{name} (you)", { name: a.name }) : a.name,
    })),
  ];
  if (conversation.assignee && !agents.some((a) => a.id === conversation.assignee.id)) {
    assigneeOptions.push({ value: String(conversation.assignee.id), label: conversation.assignee.name });
  }

  const menuItems = [
    { content: t("header.mark_unread", "Mark as unread"), onAction: onMarkUnread },
    conversation.opted_out
      ? { content: t("header.unblock", "Unblock customer"), onAction: onBlockToggle }
      : { content: t("header.block", "Block customer"), destructive: true, onAction: onBlockToggle },
  ];

  return (
    <Box padding="300" borderBlockEndWidth="025" borderColor="border-secondary">
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center" wrap={false} gap="200">
          <InlineStack gap="200" blockAlign="center" wrap={false}>
            {onBack && (
              <Button icon={ArrowLeftMinor} variant="tertiary" onClick={onBack} accessibilityLabel={t("header.back", "Back to conversations")} />
            )}
            <Box minWidth="0">
              <BlockStack gap="050">
                <Text as="h2" variant="headingMd" truncate>
                  {name}
                </Text>
                <InlineStack gap="200" blockAlign="center">
                  {conversation.customer?.name && (
                    <Text as="span" variant="bodySm" tone="subdued">
                      {phone}
                    </Text>
                  )}
                  {win.open ? (
                    <Badge tone={win.urgent ? "warning" : "success"} size="small">
                      {t("header.window_closes_in", "Reply window closes in %{time}", { time: win.left })}
                    </Badge>
                  ) : (
                    <Badge size="small">{t("header.window_closed", "Reply window closed")}</Badge>
                  )}
                  {conversation.opted_out && (
                    <Badge tone="critical" size="small">
                      {t("header.blocked", "Blocked")}
                    </Badge>
                  )}
                </InlineStack>
              </BlockStack>
            </Box>
          </InlineStack>
          <InlineStack gap="100" wrap={false}>
            {onOpenCustomer && (
              <Button
                icon={CustomersMajor}
                variant="tertiary"
                onClick={onOpenCustomer}
                accessibilityLabel={t("header.customer", "Customer details")}
              />
            )}
            <Popover
              active={menuOpen}
              onClose={() => setMenuOpen(false)}
              preferredAlignment="right"
              activator={
                <Button
                  icon={HorizontalDotsMinor}
                  variant="tertiary"
                  disabled={busy}
                  onClick={() => setMenuOpen((v) => !v)}
                  accessibilityLabel={t("header.more_actions", "More actions")}
                />
              }
            >
              <ActionList actionRole="menuitem" items={menuItems} onActionAnyItem={() => setMenuOpen(false)} />
            </Popover>
          </InlineStack>
        </InlineStack>
        <InlineStack gap="200" blockAlign="center">
          <div style={{ minWidth: 130 }}>
            <Select
              label={t("header.status", "Status")}
              labelHidden
              options={statusOptions}
              value={conversation.status}
              disabled={busy}
              onChange={(status) => onUpdate({ status })}
            />
          </div>
          <div style={{ minWidth: 160 }}>
            <Select
              label={t("header.assign", "Assign to")}
              labelHidden
              options={assigneeOptions}
              value={conversation.assignee ? String(conversation.assignee.id) : ""}
              disabled={busy}
              onChange={(value) => onUpdate({ assignee_id: value ? Number(value) : null })}
            />
          </div>
          <LabelPicker labels={labels} selected={selectedLabels} onChange={onLabels} disabled={busy} />
          {(conversation.labels || []).map((label) => (
            <Badge key={label.id} tone={label.color || "info"}>
              {label.name}
            </Badge>
          ))}
        </InlineStack>
      </BlockStack>
    </Box>
  );
};

export default ConversationHeader;
