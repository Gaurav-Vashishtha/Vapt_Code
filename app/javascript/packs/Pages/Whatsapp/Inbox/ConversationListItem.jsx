import React from "react";
import { Avatar, Badge, BlockStack, Box, InlineStack, Text, Tooltip } from "@shopify/polaris";
import { customerName, initials, relativeTime, t, windowState } from "./format";

const MAX_LABELS = 2;

const ConversationListItem = ({ conversation, selected, onSelect, now }) => {
  const name = customerName(conversation.customer);
  const unread = Number(conversation.unread_count || 0);
  const win = windowState(conversation, now);
  const labels = conversation.labels || [];
  const last = conversation.last_message || {};
  const preview = last.direction === "outbound" ? t("list.you_prefix", "You: %{text}", { text: last.preview || "" }) : last.preview;
  const assignee = conversation.assignee;

  const activate = () => onSelect(conversation.id);

  return (
    <div
      role="button"
      tabIndex={0}
      aria-current={selected ? "true" : undefined}
      onClick={activate}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          activate();
        }
      }}
      style={{ cursor: "pointer", outlineOffset: -2 }}
    >
      <Box
        padding="300"
        background={selected ? "bg-surface-selected" : "bg-surface"}
        borderBlockEndWidth="025"
        borderColor="border-secondary"
      >
        <BlockStack gap="100">
          <InlineStack align="space-between" blockAlign="center" wrap={false} gap="200">
            <Box minWidth="0">
              <Text as="span" variant="bodyMd" fontWeight={unread > 0 ? "bold" : "medium"} truncate>
                {name}
              </Text>
            </Box>
            <InlineStack gap="100" blockAlign="center" wrap={false}>
              <Text as="span" variant="bodySm" tone="subdued">
                {relativeTime(last.at || conversation.last_inbound_at, now)}
              </Text>
              {unread > 0 && (
                <Badge tone="info" size="small">
                  {String(unread)}
                </Badge>
              )}
            </InlineStack>
          </InlineStack>
          <Text as="p" variant="bodySm" tone={unread > 0 ? undefined : "subdued"} truncate>
            {preview || " "}
          </Text>
          <InlineStack align="space-between" blockAlign="center" wrap={false} gap="100">
            <InlineStack gap="100">
              {win.open ? (
                <Badge tone={win.urgent ? "warning" : undefined} size="small">
                  {t("list.window_left", "%{time} left", { time: win.left })}
                </Badge>
              ) : (
                <Badge size="small">{t("list.window_closed", "Window closed")}</Badge>
              )}
              {labels.slice(0, MAX_LABELS).map((label) => (
                <Badge key={label.id} tone={label.color || "info"} size="small">
                  {label.name}
                </Badge>
              ))}
              {labels.length > MAX_LABELS && <Badge size="small">{`+${labels.length - MAX_LABELS}`}</Badge>}
            </InlineStack>
            {assignee && (
              <Tooltip content={assignee.name}>
                <Avatar size="xs" initials={initials(assignee.name)} name={assignee.name} />
              </Tooltip>
            )}
          </InlineStack>
        </BlockStack>
      </Box>
    </div>
  );
};

export default ConversationListItem;
