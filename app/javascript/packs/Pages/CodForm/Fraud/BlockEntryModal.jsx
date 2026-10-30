import React, { useEffect, useMemo, useState } from "react";
import { Modal, Banner, BlockStack, ChoiceList, DropZone, Text, TextField } from "@shopify/polaris";
import { SaveErrorBanner } from "../components/Screen";
import { LIMITS } from "../constants";
import { splitEntries } from "../utils";
import { t } from "../i18n";

const IPV4 = /^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}(\/(3[0-2]|[12]?\d))?$/;
const IPV6 = /^[0-9a-f:]+(\/\d{1,3})?$/i;

/** Same acceptance as CodForm::BlockEntry.normalize: phone digits, email or *@domain, IP or CIDR. */
export const isValidEntry = (kind, raw) => {
  const value = String(raw || "").trim();
  if (!value) return false;
  if (kind === "phone") {
    const digits = value.replace(/\D/g, "");
    return digits.length >= 6 && digits.length <= 15;
  }
  if (kind === "email") return /^(\*|[^\s@]+)@[^\s@]+\.[^\s@]+$/.test(value);
  return IPV4.test(value) || (value.includes(":") && IPV6.test(value));
};

/** Add one entry, or paste / upload a list (max 5 000 per request). */
const BlockEntryModal = ({ open, kind, saving, error, onClose, onSubmit }) => {
  const [mode, setMode] = useState("single");
  const [value, setValue] = useState("");
  const [note, setNote] = useState("");
  const [bulk, setBulk] = useState("");
  const [fileName, setFileName] = useState("");

  useEffect(() => {
    if (open) {
      setMode("single");
      setValue("");
      setNote("");
      setBulk("");
      setFileName("");
    }
  }, [open, kind]);

  const parsed = useMemo(() => {
    const entries = splitEntries(bulk);
    const valid = entries.filter((entry) => isValidEntry(kind, entry));
    return { total: entries.length, valid, invalid: entries.length - valid.length };
  }, [bulk, kind]);

  const overLimit = parsed.valid.length > LIMITS.BLOCK_ENTRIES_PER_KIND;
  const singleValid = isValidEntry(kind, value);

  const readFile = (files) => {
    const file = files && files[0];
    if (!file) return;
    setFileName(file.name);
    const reader = new FileReader();
    reader.onload = () => setBulk(String(reader.result || ""));
    reader.readAsText(file);
  };

  const label =
    kind === "phone"
      ? t("fraud.entry_phone", "Phone number")
      : kind === "email"
      ? t("fraud.entry_email", "Email address")
      : t("fraud.entry_ip", "IP address");
  const help =
    kind === "phone"
      ? t("fraud.entry_phone_help", "With or without the country code. Spaces and symbols are ignored.")
      : kind === "email"
      ? t("fraud.entry_email_help", "A full address, or *@domain.com to block a whole domain.")
      : t("fraud.entry_ip_help", "A single address, or a range such as 10.0.0.0/8.");

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t("fraud.block_add", "Add to block list")}
      primaryAction={{
        content: t("common.add", "Add"),
        loading: saving,
        disabled: mode === "single" ? !singleValid : parsed.valid.length === 0 || overLimit,
        onAction: () =>
          mode === "single"
            ? onSubmit({ kind, value: value.trim(), note: note.trim() })
            : onSubmit({ kind, values: parsed.valid }),
      }}
      secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="400">
          <SaveErrorBanner error={error} />
          <ChoiceList
            title={t("fraud.entry_mode", "How to add")}
            titleHidden
            choices={[
              { label: t("fraud.entry_mode_single", "One entry"), value: "single" },
              { label: t("fraud.block_bulk", "Paste or upload a list"), value: "bulk" },
            ]}
            selected={[mode]}
            onChange={(next) => setMode(next[0])}
          />
          {mode === "single" ? (
            <>
              <TextField
                label={label}
                value={value}
                onChange={setValue}
                helpText={help}
                error={value && !singleValid ? t("fraud.entry_invalid", "This does not look right. Check the format.") : undefined}
                autoComplete="off"
              />
              <TextField
                label={t("fraud.entry_note", "Note (optional)")}
                value={note}
                onChange={setNote}
                maxLength={120}
                placeholder={t("fraud.entry_note_placeholder", "Refused 3 parcels")}
                autoComplete="off"
              />
            </>
          ) : (
            <>
              <TextField
                label={t("fraud.bulk_label", "One entry per line, or separated by commas")}
                value={bulk}
                onChange={setBulk}
                multiline={6}
                helpText={help}
                autoComplete="off"
              />
              <DropZone accept=".txt,.csv,text/plain,text/csv" type="file" allowMultiple={false} onDrop={(_all, accepted) => readFile(accepted)}>
                {fileName ? (
                  <div style={{ padding: 16 }}>
                    <Text as="p" fontWeight="semibold">
                      {fileName}
                    </Text>
                  </div>
                ) : (
                  <DropZone.FileUpload actionTitle={t("fraud.bulk_upload", "Upload a .txt or .csv file")} />
                )}
              </DropZone>
              {parsed.total > 0 && (
                <Banner tone={overLimit ? "critical" : parsed.invalid ? "warning" : "info"}>
                  <p>
                    {overLimit
                      ? t("fraud.bulk_over_limit", "You can add up to 5,000 entries at a time. This list has %{count}.", { count: parsed.valid.length })
                      : t("fraud.bulk_summary", "%{valid} entries will be added. %{invalid} are not valid and will be skipped.", {
                          valid: parsed.valid.length,
                          invalid: parsed.invalid,
                        })}
                  </p>
                </Banner>
              )}
            </>
          )}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

export default BlockEntryModal;
