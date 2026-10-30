import React, { useCallback, useEffect, useState } from "react";
import {
  BlockStack,
  InlineStack,
  Box,
  Text,
  Button,
  TextField,
  Modal,
  Banner,
  Divider,
  SkeletonBodyText,
} from "@shopify/polaris";
import { PlusMinor, EditMinor, DeleteMinor } from "@shopify/polaris-icons";
import I18n from "../../../../i18n-lang";
import { api } from "../../Campaigns/api";
import { VariableButtons, appendToken } from "./KeywordRulesEditor";

const t = (key, defaultValue, opts = {}) =>
  I18n.t(`whatsapp_inbox_settings.${key}`, { defaultValue, ...opts });

const BASE = "/api/whatsapp/inbox/saved_replies";
const EMPTY_FORM = { title: "", shortcut: "", body: "" };

const toShortcut = (value) =>
  value
    .replace(/^\//, "")
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/[^\p{L}\p{N}_-]/gu, "")
    .slice(0, 30);

const ReplyModal = ({ open, reply, variables, onClose, onSaved }) => {
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (open) {
      setForm(reply ? { title: reply.title, shortcut: reply.shortcut, body: reply.body } : EMPTY_FORM);
      setError(null);
    }
  }, [open, reply]);

  const set = (key) => (value) =>
    setForm((f) => ({ ...f, [key]: key === "shortcut" ? toShortcut(value) : value }));

  const canSave = form.title.trim() && form.shortcut.trim() && form.body.trim();

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      const data = await api(reply ? `${BASE}/${reply.id}` : BASE, {
        method: reply ? "PATCH" : "POST",
        body: form,
      });
      onSaved(data.saved_reply);
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={reply ? t("saved_replies.edit_title", "Edit saved reply") : t("saved_replies.add", "Add saved reply")}
      primaryAction={{ content: t("save", "Save"), onAction: save, loading: saving, disabled: !canSave }}
      secondaryActions={[{ content: t("cancel", "Cancel"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="300">
          {error && <Banner tone="critical">{error}</Banner>}
          <TextField
            label={t("saved_replies.title_field", "Title")}
            value={form.title}
            onChange={set("title")}
            maxLength={60}
            autoComplete="off"
            placeholder={t("saved_replies.title_placeholder", "e.g. Order tracking")}
          />
          <TextField
            label={t("saved_replies.shortcut", "Shortcut")}
            value={form.shortcut}
            onChange={set("shortcut")}
            prefix="/"
            maxLength={30}
            autoComplete="off"
            helpText={t("saved_replies.shortcut_help", "Type / and this shortcut in a reply to insert the message.")}
          />
          <TextField
            label={t("saved_replies.body", "Message")}
            value={form.body}
            onChange={set("body")}
            multiline={4}
            maxLength={4096}
            showCharacterCount
            autoComplete="off"
          />
          <VariableButtons
            variables={variables}
            onInsert={(token) => setForm((f) => ({ ...f, body: appendToken(f.body, token) }))}
          />
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

const SavedRepliesManager = ({ variables }) => {
  const [replies, setReplies] = useState(null);
  const [error, setError] = useState(null);
  const [editing, setEditing] = useState(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [deleting, setDeleting] = useState(null);
  const [deleteBusy, setDeleteBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const data = await api(BASE);
      setReplies(data.saved_replies || []);
    } catch (e) {
      setError(e.message);
      setReplies([]);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const openModal = (reply) => {
    setEditing(reply);
    setModalOpen(true);
  };

  const onSaved = (saved) => {
    setModalOpen(false);
    setReplies((list) => {
      const current = list || [];
      return current.some((r) => r.id === saved.id)
        ? current.map((r) => (r.id === saved.id ? saved : r))
        : [saved, ...current];
    });
  };

  const confirmDelete = async () => {
    setDeleteBusy(true);
    try {
      await api(`${BASE}/${deleting.id}`, { method: "DELETE" });
      setReplies((list) => list.filter((r) => r.id !== deleting.id));
      setDeleting(null);
    } catch (e) {
      setError(e.message);
      setDeleting(null);
    } finally {
      setDeleteBusy(false);
    }
  };

  return (
    <BlockStack gap="300">
      {error && (
        <Banner tone="critical" onDismiss={() => setError(null)}>
          {error}
        </Banner>
      )}
      {replies === null ? (
        <SkeletonBodyText lines={3} />
      ) : replies.length === 0 ? (
        <Text as="p" tone="subdued">
          {t("saved_replies.empty", "No saved replies yet. Save answers you send often and insert them with /.")}
        </Text>
      ) : (
        <BlockStack gap="300">
          {replies.map((reply, index) => (
            <BlockStack key={reply.id} gap="300">
              {index > 0 && <Divider />}
              <InlineStack align="space-between" blockAlign="start" gap="200" wrap={false}>
                <Box minWidth="0">
                  <BlockStack gap="100">
                    <InlineStack gap="200" blockAlign="center">
                      <Text as="span" fontWeight="semibold">
                        {reply.title}
                      </Text>
                      <Text as="span" tone="subdued">
                        /{reply.shortcut}
                      </Text>
                    </InlineStack>
                    <Text as="p" tone="subdued" truncate>
                      {reply.body}
                    </Text>
                  </BlockStack>
                </Box>
                <InlineStack gap="100" wrap={false}>
                  <Button
                    icon={EditMinor}
                    variant="tertiary"
                    accessibilityLabel={t("saved_replies.edit_title", "Edit saved reply")}
                    onClick={() => openModal(reply)}
                  />
                  <Button
                    icon={DeleteMinor}
                    variant="tertiary"
                    tone="critical"
                    accessibilityLabel={t("saved_replies.delete", "Delete saved reply")}
                    onClick={() => setDeleting(reply)}
                  />
                </InlineStack>
              </InlineStack>
            </BlockStack>
          ))}
        </BlockStack>
      )}
      <Box>
        <Button icon={PlusMinor} onClick={() => openModal(null)}>
          {t("saved_replies.add", "Add saved reply")}
        </Button>
      </Box>
      <ReplyModal
        open={modalOpen}
        reply={editing}
        variables={variables}
        onClose={() => setModalOpen(false)}
        onSaved={onSaved}
      />
      <Modal
        open={Boolean(deleting)}
        onClose={() => setDeleting(null)}
        title={t("saved_replies.delete", "Delete saved reply")}
        primaryAction={{
          content: t("delete", "Delete"),
          destructive: true,
          loading: deleteBusy,
          onAction: confirmDelete,
        }}
        secondaryActions={[{ content: t("cancel", "Cancel"), onAction: () => setDeleting(null) }]}
      >
        <Modal.Section>
          <Text as="p">
            {t("saved_replies.delete_confirm", "Delete \"%{title}\"? This can't be undone.", {
              title: deleting?.title || "",
            })}
          </Text>
        </Modal.Section>
      </Modal>
    </BlockStack>
  );
};

export default SavedRepliesManager;
