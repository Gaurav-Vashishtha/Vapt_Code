import React, { useCallback, useEffect, useState } from "react";
import {
  BlockStack,
  InlineStack,
  Box,
  Text,
  Button,
  Badge,
  TextField,
  Select,
  Modal,
  Banner,
  Divider,
  SkeletonBodyText,
} from "@shopify/polaris";
import { PlusMinor, EditMinor, DeleteMinor } from "@shopify/polaris-icons";
import I18n from "../../../../i18n-lang";
import { api } from "../../Campaigns/api";

const t = (key, defaultValue, opts = {}) =>
  I18n.t(`whatsapp_inbox_settings.${key}`, { defaultValue, ...opts });

const BASE = "/api/whatsapp/inbox/labels";

const COLOR_OPTIONS = () => [
  { label: t("labels.colors.info", "Blue"), value: "info" },
  { label: t("labels.colors.success", "Green"), value: "success" },
  { label: t("labels.colors.warning", "Yellow"), value: "warning" },
  { label: t("labels.colors.critical", "Red"), value: "critical" },
  { label: t("labels.colors.attention", "Orange"), value: "attention" },
  { label: t("labels.colors.new", "Grey"), value: "new" },
];

const LabelModal = ({ open, label, onClose, onSaved }) => {
  const [name, setName] = useState("");
  const [color, setColor] = useState("info");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (open) {
      setName(label?.name || "");
      setColor(label?.color || "info");
      setError(null);
    }
  }, [open, label]);

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      const data = await api(label ? `${BASE}/${label.id}` : BASE, {
        method: label ? "PATCH" : "POST",
        body: { name, color },
      });
      onSaved(data.label);
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
      title={label ? t("labels.edit_title", "Edit label") : t("labels.add", "Add label")}
      primaryAction={{ content: t("save", "Save"), onAction: save, loading: saving, disabled: !name.trim() }}
      secondaryActions={[{ content: t("cancel", "Cancel"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="300">
          {error && <Banner tone="critical">{error}</Banner>}
          <TextField
            label={t("labels.name", "Name")}
            value={name}
            onChange={setName}
            maxLength={40}
            autoComplete="off"
          />
          <Select label={t("labels.color", "Color")} options={COLOR_OPTIONS()} value={color} onChange={setColor} />
          <InlineStack gap="200" blockAlign="center">
            <Text as="span" tone="subdued">
              {t("labels.preview", "Preview")}
            </Text>
            <Badge tone={color}>{name.trim() || t("labels.name", "Name")}</Badge>
          </InlineStack>
          {label?.system_key && (
            <Text as="p" variant="bodySm" tone="subdued">
              {t("labels.system_hint", "Built-in label. You can rename it, but not delete it.")}
            </Text>
          )}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

const LabelsManager = () => {
  const [labels, setLabels] = useState(null);
  const [error, setError] = useState(null);
  const [editing, setEditing] = useState(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [deleting, setDeleting] = useState(null);
  const [deleteBusy, setDeleteBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const data = await api(BASE);
      setLabels(data.labels || []);
    } catch (e) {
      setError(e.message);
      setLabels([]);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const openModal = (label) => {
    setEditing(label);
    setModalOpen(true);
  };

  const onSaved = (saved) => {
    setModalOpen(false);
    setLabels((list) => {
      const current = list || [];
      return current.some((l) => l.id === saved.id)
        ? current.map((l) => (l.id === saved.id ? saved : l))
        : [...current, saved];
    });
  };

  const confirmDelete = async () => {
    setDeleteBusy(true);
    try {
      await api(`${BASE}/${deleting.id}`, { method: "DELETE" });
      setLabels((list) => list.filter((l) => l.id !== deleting.id));
    } catch (e) {
      setError(e.message);
    } finally {
      setDeleting(null);
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
      {labels === null ? (
        <SkeletonBodyText lines={3} />
      ) : (
        <BlockStack gap="200">
          {labels.map((label, index) => (
            <BlockStack key={label.id} gap="200">
              {index > 0 && <Divider />}
              <InlineStack align="space-between" blockAlign="center" gap="200" wrap={false}>
                <InlineStack gap="200" blockAlign="center">
                  <Badge tone={label.color}>{label.name}</Badge>
                  {label.system_key && (
                    <Text as="span" variant="bodySm" tone="subdued">
                      {t("labels.built_in", "Built-in")}
                    </Text>
                  )}
                </InlineStack>
                <InlineStack gap="100" wrap={false}>
                  <Button
                    icon={EditMinor}
                    variant="tertiary"
                    accessibilityLabel={t("labels.edit_title", "Edit label")}
                    onClick={() => openModal(label)}
                  />
                  {!label.system_key && (
                    <Button
                      icon={DeleteMinor}
                      variant="tertiary"
                      tone="critical"
                      accessibilityLabel={t("labels.delete", "Delete label")}
                      onClick={() => setDeleting(label)}
                    />
                  )}
                </InlineStack>
              </InlineStack>
            </BlockStack>
          ))}
        </BlockStack>
      )}
      <Box>
        <Button icon={PlusMinor} onClick={() => openModal(null)}>
          {t("labels.add", "Add label")}
        </Button>
      </Box>
      <LabelModal open={modalOpen} label={editing} onClose={() => setModalOpen(false)} onSaved={onSaved} />
      <Modal
        open={Boolean(deleting)}
        onClose={() => setDeleting(null)}
        title={t("labels.delete", "Delete label")}
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
            {t("labels.delete_confirm", "Delete \"%{name}\"? It will be removed from every conversation.", {
              name: deleting?.name || "",
            })}
          </Text>
        </Modal.Section>
      </Modal>
    </BlockStack>
  );
};

export default LabelsManager;
