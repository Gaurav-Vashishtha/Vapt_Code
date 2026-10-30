import React, { useEffect, useMemo, useState } from "react";
import { Badge, Banner, BlockStack, Box, Checkbox, Icon, InlineStack, Modal, Spinner, Text, TextField } from "@shopify/polaris";
import { SearchMinor } from "@shopify/polaris-icons";
import { inboxApi } from "./api";
import { errorMessage, fillTemplate, t } from "./format";

const initialParams = (template) =>
  Object.fromEntries((template.placeholders || []).map((key) => [key, String(template.prefill?.[key] ?? "")]));

const TemplateRow = ({ template, onPick }) => (
  <div
    role="button"
    tabIndex={0}
    style={{ cursor: "pointer" }}
    onClick={() => onPick(template)}
    onKeyDown={(e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        onPick(template);
      }
    }}
  >
    <Box padding="300" borderWidth="025" borderColor="border" borderRadius="200">
      <BlockStack gap="100">
        <InlineStack gap="200" blockAlign="center">
          <Text as="span" fontWeight="semibold">
            {template.name}
          </Text>
          <Badge size="small">{template.language}</Badge>
          {template.category && <Badge size="small" tone={template.category === "MARKETING" ? "attention" : "info"}>{template.category.charAt(0) + template.category.slice(1).toLowerCase()}</Badge>}
        </InlineStack>
        <Text as="p" variant="bodySm" tone="subdued" truncate>
          {template.body_text}
        </Text>
      </BlockStack>
    </Box>
  </div>
);

const TemplatePicker = ({ open, conversationId, onClose, onSend }) => {
  const [templates, setTemplates] = useState(null);
  const [loadError, setLoadError] = useState("");
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(null);
  const [params, setParams] = useState({});
  const [resolve, setResolve] = useState(false);
  const [sending, setSending] = useState(false);
  const [sendError, setSendError] = useState("");

  useEffect(() => {
    if (!open) return undefined;
    let alive = true;
    setTemplates(null);
    setLoadError("");
    setSelected(null);
    setQuery("");
    setSendError("");
    setResolve(false);
    inboxApi
      .templates(conversationId)
      .then((data) => alive && setTemplates(data.templates || []))
      .catch((e) => {
        if (!alive) return;
        setLoadError(e.message);
        setTemplates([]);
      });
    return () => {
      alive = false;
    };
  }, [open, conversationId]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return templates || [];
    return (templates || []).filter(
      (tpl) => tpl.name.toLowerCase().includes(q) || String(tpl.body_text || "").toLowerCase().includes(q),
    );
  }, [templates, query]);

  const pick = (template) => {
    setSelected(template);
    setParams(initialParams(template));
    setSendError("");
  };

  const missing = selected ? (selected.placeholders || []).some((key) => !String(params[key] || "").trim()) : true;

  const send = async () => {
    if (!selected || missing) return;
    setSending(true);
    setSendError("");
    try {
      await onSend({
        templateId: selected.id,
        bodyParameters: (selected.placeholders || []).map((key) => String(params[key]).trim()),
        resolve,
      });
      onClose();
    } catch (e) {
      setSendError(errorMessage(e));
    } finally {
      setSending(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t("template_picker.title", "Send a template")}
      primaryAction={
        selected
          ? { content: t("template_picker.send", "Send template"), onAction: send, loading: sending, disabled: missing }
          : undefined
      }
      secondaryActions={[
        selected
          ? { content: t("template_picker.back", "Choose another"), onAction: () => setSelected(null), disabled: sending }
          : { content: t("template_picker.cancel", "Cancel"), onAction: onClose },
      ]}
    >
      <Modal.Section>
        {templates === null ? (
          <InlineStack align="center">
            <Spinner size="small" />
          </InlineStack>
        ) : selected ? (
          <BlockStack gap="300">
            {sendError && <Banner tone="critical">{sendError}</Banner>}
            <Box padding="300" background="bg-surface-success" borderRadius="300">
              <Text as="p">
                <span style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{fillTemplate(selected.body_text, params)}</span>
              </Text>
            </Box>
            {selected.header_type && !["none", "text"].includes(selected.header_type) && (
              <Text as="p" variant="bodySm" tone="subdued">
                {t("template_picker.media_header", "The template's saved header is sent with it.")}
              </Text>
            )}
            {(selected.placeholders || []).length > 0 && (
              <BlockStack gap="200">
                <Text as="h3" variant="headingSm">
                  {t("template_picker.variables", "Fill in the details")}
                </Text>
                {selected.placeholders.map((key) => (
                  <TextField
                    key={key}
                    label={`{{${key}}}`}
                    value={params[key] || ""}
                    onChange={(value) => setParams((prev) => ({ ...prev, [key]: value }))}
                    autoComplete="off"
                  />
                ))}
              </BlockStack>
            )}
            <Checkbox
              label={t("template_picker.resolve", "Mark as resolved after sending")}
              checked={resolve}
              onChange={setResolve}
            />
          </BlockStack>
        ) : (
          <BlockStack gap="300">
            {loadError && <Banner tone="critical">{loadError}</Banner>}
            <TextField
              label={t("template_picker.search", "Search templates")}
              labelHidden
              placeholder={t("template_picker.search", "Search templates")}
              value={query}
              onChange={setQuery}
              prefix={<Icon source={SearchMinor} tone="subdued" />}
              autoComplete="off"
            />
            {visible.length === 0 ? (
              <Text as="p" tone="subdued">
                {t(
                  "template_picker.no_templates",
                  "No approved templates for this number yet. Create one on the WhatsApp templates page.",
                )}
              </Text>
            ) : (
              visible.map((template) => <TemplateRow key={template.id} template={template} onPick={pick} />)
            )}
          </BlockStack>
        )}
      </Modal.Section>
    </Modal>
  );
};

export default TemplatePicker;
