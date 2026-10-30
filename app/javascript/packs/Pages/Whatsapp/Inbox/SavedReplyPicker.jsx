import React from "react";
import { ActionList, Box, Spinner, Text } from "@shopify/polaris";
import { t } from "./format";

const MAX_RESULTS = 8;

export const filterSavedReplies = (replies, query) => {
  const q = String(query || "").toLowerCase();
  const list = replies || [];
  const matches = q
    ? list.filter(
        (r) => String(r.shortcut || "").toLowerCase().includes(q) || String(r.title || "").toLowerCase().includes(q),
      )
    : list;
  return [...matches]
    .sort((a, b) => {
      const aStarts = String(a.shortcut || "").toLowerCase().startsWith(q) ? 0 : 1;
      const bStarts = String(b.shortcut || "").toLowerCase().startsWith(q) ? 0 : 1;
      return aStarts - bStarts || (b.usage_count || 0) - (a.usage_count || 0);
    })
    .slice(0, MAX_RESULTS);
};

const SavedReplyPicker = ({ matches, loading, highlight, onSelect }) => {
  if (loading) {
    return (
      <Box padding="300">
        <Spinner size="small" accessibilityLabel={t("composer.saved_replies", "Saved replies")} />
      </Box>
    );
  }
  if (!matches.length) {
    return (
      <Box padding="300" maxWidth="360px">
        <Text as="p" tone="subdued">
          {t("composer.no_saved_replies", "No saved replies match. Add them in inbox settings.")}
        </Text>
      </Box>
    );
  }
  return (
    <ActionList
      actionRole="menuitem"
      items={matches.map((reply, index) => ({
        id: `saved-reply-${reply.id}`,
        content: reply.title,
        suffix: (
          <Text as="span" variant="bodySm" tone="subdued">
            {`/${reply.shortcut}`}
          </Text>
        ),
        helpText: String(reply.body || "").slice(0, 80),
        active: index === highlight,
        onAction: () => onSelect(reply),
      }))}
    />
  );
};

export default SavedReplyPicker;
