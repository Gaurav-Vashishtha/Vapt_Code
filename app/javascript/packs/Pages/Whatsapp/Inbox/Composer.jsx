import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Banner, BlockStack, Button, ButtonGroup, InlineStack, Popover, Tag, Text, TextField } from "@shopify/polaris";
import { AttachmentMajor, ChatMajor, SendMajor } from "@shopify/polaris-icons";
import EmojiPicker from "./EmojiPicker";
import SavedReplyPicker, { filterSavedReplies } from "./SavedReplyPicker";
import { inboxApi } from "./api";
import { formatFileSize, substituteVariables, t } from "./format";

const SLASH_RE = /(^|\s)\/([^\s/]*)$/;
const IMAGE_TYPES = ["image/jpeg", "image/png"];
const PDF_TYPE = "application/pdf";
const IMAGE_LIMIT = 5 * 1024 * 1024;
const PDF_LIMIT = 16 * 1024 * 1024;

const validateFile = (file) => {
  if (IMAGE_TYPES.includes(file.type)) {
    return file.size > IMAGE_LIMIT ? t("composer.file_too_large", "This file is too large. Images can be up to 5 MB and PDFs up to 16 MB.") : null;
  }
  if (file.type === PDF_TYPE) {
    return file.size > PDF_LIMIT ? t("composer.file_too_large", "This file is too large. Images can be up to 5 MB and PDFs up to 16 MB.") : null;
  }
  return t("composer.file_type", "You can attach JPG or PNG images and PDF files.");
};

const Composer = ({ conversation, windowOpen, onSend, onOpenTemplates, insert }) => {
  const [text, setText] = useState("");
  const [file, setFile] = useState(null);
  const [fileError, setFileError] = useState("");
  const [sending, setSending] = useState(false);
  const [picker, setPicker] = useState({ open: false, query: "" });
  const [highlight, setHighlight] = useState(0);
  const [replies, setReplies] = useState(null);
  const [repliesLoading, setRepliesLoading] = useState(false);
  const fileInput = useRef(null);
  const variables = conversation?.variables;

  const seenInsert = useRef(insert?.nonce);

  useEffect(() => {
    if (!insert?.text || insert.nonce === seenInsert.current) return;
    seenInsert.current = insert.nonce;
    setText((prev) => {
      if (!prev) return insert.text;
      return /\s$/.test(prev) ? `${prev}${insert.text}` : `${prev} ${insert.text}`;
    });
  }, [insert]);

  const loadReplies = useCallback(async () => {
    if (replies || repliesLoading) return;
    setRepliesLoading(true);
    try {
      const data = await inboxApi.savedReplies();
      setReplies(data.saved_replies || []);
    } catch (e) {
      setReplies([]);
    } finally {
      setRepliesLoading(false);
    }
  }, [replies, repliesLoading]);

  const matches = useMemo(
    () => (picker.open ? filterSavedReplies(replies, picker.query) : []),
    [picker, replies],
  );

  const closePicker = () => setPicker({ open: false, query: "" });

  const handleChange = (value) => {
    setText(value);
    const match = value.match(SLASH_RE);
    if (match) {
      setPicker({ open: true, query: match[2] });
      setHighlight(0);
      loadReplies();
    } else if (picker.open) {
      closePicker();
    }
  };

  const selectReply = (reply) => {
    const body = substituteVariables(reply.body, variables);
    setText((prev) => (SLASH_RE.test(prev) ? prev.replace(SLASH_RE, (all, lead) => `${lead}${body}`) : `${prev}${body}`));
    closePicker();
    inboxApi.savedReplyUsed(reply.id).catch(() => {});
  };

  const expandShortcut = (value) => {
    const m = value.match(/^\/([^\s/]+)$/);
    if (!m || !replies) return value;
    const reply = replies.find((r) => String(r.shortcut || "").toLowerCase() === m[1].toLowerCase());
    if (!reply) return value;
    inboxApi.savedReplyUsed(reply.id).catch(() => {});
    return substituteVariables(reply.body, variables)
      .replace(/\{\{\s*[a-z_]+\s*\}\}/gi, "")
      .replace(/[ \t]{2,}/g, " ")
      .trim();
  };

  const submit = async (resolve) => {
    if (sending) return;
    const trimmed = expandShortcut(text.trim());
    if (!file && !trimmed) return;
    setSending(true);
    const ok = await onSend(
      file ? { type: "media", file, caption: trimmed, resolve } : { type: "text", text: trimmed, resolve },
    );
    setSending(false);
    if (ok) {
      setText("");
      setFile(null);
      closePicker();
    }
  };

  const onKeyDown = (e) => {
    if (picker.open) {
      if (e.key === "Escape") {
        e.preventDefault();
        closePicker();
        return;
      }
      if (matches.length && (e.key === "ArrowDown" || e.key === "ArrowUp")) {
        e.preventDefault();
        const step = e.key === "ArrowDown" ? 1 : -1;
        setHighlight((h) => (h + step + matches.length) % matches.length);
        return;
      }
      if (matches.length && e.key === "Enter" && !e.shiftKey && !e.metaKey && !e.ctrlKey) {
        e.preventDefault();
        selectReply(matches[Math.min(highlight, matches.length - 1)]);
        return;
      }
    }
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      submit(false);
    }
  };

  const onFile = (e) => {
    const picked = e.target.files && e.target.files[0];
    e.target.value = "";
    if (!picked) return;
    const problem = validateFile(picked);
    setFileError(problem || "");
    setFile(problem ? null : picked);
  };

  if (!windowOpen) {
    return (
      <Banner
        tone="warning"
        title={t("composer.window_closed_title", "The 24-hour reply window has closed")}
        action={{ content: t("composer.send_template", "Send a template"), onAction: onOpenTemplates }}
      >
        <p>{t("composer.window_closed_body", "WhatsApp only allows approved templates now. The window opens again when the customer replies.")}</p>
      </Banner>
    );
  }

  const field = (
    <TextField
      label={t("composer.label", "Reply")}
      labelHidden
      value={text}
      onChange={handleChange}
      multiline={3}
      maxHeight={200}
      autoComplete="off"
      placeholder={
        file
          ? t("composer.caption_placeholder", "Add a caption (optional)")
          : t("composer.placeholder", "Type a reply. Type / for saved replies")
      }
      disabled={sending}
      ariaExpanded={picker.open}
    />
  );

  return (
    <BlockStack gap="200">
      {conversation?.opted_out && (
        <Banner tone="info">
          <p>{t("composer.opted_out_note", "Customer unsubscribed from marketing. Service replies still work.")}</p>
        </Banner>
      )}
      {fileError && (
        <Text as="p" tone="critical" variant="bodySm">
          {fileError}
        </Text>
      )}
      {file && (
        <InlineStack>
          <Tag onRemove={() => setFile(null)}>{`${file.name} · ${formatFileSize(file.size)}`}</Tag>
        </InlineStack>
      )}
      <div onKeyDown={onKeyDown}>
        <Popover
          active={picker.open}
          activator={field}
          onClose={closePicker}
          autofocusTarget="none"
          preferredPosition="above"
          preferredAlignment="left"
          fullWidth
        >
          <SavedReplyPicker matches={matches} loading={repliesLoading} highlight={highlight} onSelect={selectReply} />
        </Popover>
      </div>
      <input ref={fileInput} type="file" accept="image/jpeg,image/png,application/pdf" style={{ display: "none" }} onChange={onFile} />
      <InlineStack align="space-between" blockAlign="center" gap="200">
        <InlineStack gap="100" blockAlign="center">
          <EmojiPicker disabled={sending} onPick={(emoji) => setText((prev) => `${prev}${emoji}`)} />
          <Button
            icon={AttachmentMajor}
            variant="tertiary"
            disabled={sending}
            accessibilityLabel={t("composer.attach", "Attach image or PDF")}
            onClick={() => fileInput.current && fileInput.current.click()}
          />
          <Button
            icon={ChatMajor}
            variant="tertiary"
            disabled={sending}
            accessibilityLabel={t("composer.saved_replies", "Saved replies")}
            onClick={() => handleChange(text && !/\s$/.test(text) ? `${text} /` : `${text}/`)}
          />
          <Button variant="plain" onClick={onOpenTemplates}>
            {t("composer.use_template", "Use a template")}
          </Button>
        </InlineStack>
        <ButtonGroup>
          <Button onClick={() => submit(true)} disabled={sending || (!file && !text.trim())}>
            {t("composer.send_and_resolve", "Send and resolve")}
          </Button>
          <Button
            variant="primary"
            icon={SendMajor}
            onClick={() => submit(false)}
            loading={sending}
            disabled={!file && !text.trim()}
          >
            {t("composer.send", "Send")}
          </Button>
        </ButtonGroup>
      </InlineStack>
      <Text as="p" variant="bodySm" tone="subdued">
        {t("composer.shortcut_hint", "Press Ctrl + Enter to send")}
      </Text>
    </BlockStack>
  );
};

export default Composer;
