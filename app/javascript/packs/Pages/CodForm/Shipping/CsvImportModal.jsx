import React, { useEffect, useState } from "react";
import { Modal, Banner, BlockStack, ChoiceList, DropZone, InlineStack, List, Text } from "@shopify/polaris";
import { codFormApi, parseError } from "../api";
import { SaveErrorBanner } from "../components/Screen";
import { t } from "../i18n";

const TEMPLATE =
  "name,description,price,country,province,min_total,max_total\n" +
  "Standard delivery,2-4 business days,1490,HU,,,\n" +
  "Budapest courier,Next day,990,HU,BU,,\n" +
  "Free shipping,,0,HU,,20000,\n";

/** CSV import of province-wise rates (SHP-8) with per-row errors. */
const CsvImportModal = ({ open, onClose, onImported }) => {
  const [file, setFile] = useState(null);
  const [mode, setMode] = useState("append");
  const [uploading, setUploading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [rejected, setRejected] = useState(false);

  useEffect(() => {
    if (open) {
      setFile(null);
      setMode("append");
      setResult(null);
      setError(null);
      setRejected(false);
    }
  }, [open]);

  const submit = () => {
    if (!file) return;
    setUploading(true);
    setError(null);
    codFormApi.shippingRates
      .importCsv(file, mode)
      .then((response) => {
        setResult(response || { created: 0, errors: [] });
        if (onImported) onImported();
      })
      .catch((err) => setError(parseError(err)))
      .then(() => setUploading(false));
  };

  const templateHref = `data:text/csv;charset=utf-8,${encodeURIComponent(TEMPLATE)}`;
  const rowErrors = (result && result.errors) || [];

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t("shipping.import_csv", "Import rates from CSV")}
      primaryAction={
        result
          ? { content: t("common.done", "Done"), onAction: onClose }
          : { content: t("shipping.import_cta", "Import"), onAction: submit, loading: uploading, disabled: !file }
      }
      secondaryActions={result ? undefined : [{ content: t("common.cancel", "Cancel"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="400">
          <SaveErrorBanner error={error} onDismiss={() => setError(null)} />
          {result ? (
            <>
              <Banner tone={rowErrors.length ? "warning" : "success"}>
                <p>
                  {t("shipping.import_result", "%{created} rates imported, %{failed} rows skipped.", {
                    created: result.created || 0,
                    failed: rowErrors.length,
                  })}
                </p>
              </Banner>
              {rowErrors.length > 0 && mode === "replace" && !(result.created > 0) && (
                <Text as="p">
                  {t("shipping.import_replace_nothing", "Nothing was changed: in replace mode the file must be free of errors. Fix the rows below and import again.")}
                </Text>
              )}
              {rowErrors.length > 0 && (
                <BlockStack gap="200">
                  <Text as="h3" variant="headingSm">
                    {t("shipping.import_errors_title", "Rows that were skipped")}
                  </Text>
                  <List type="bullet">
                    {rowErrors.slice(0, 50).map((item, index) => (
                      <List.Item key={`${item.row}-${index}`}>
                        {t("shipping.import_row_error", "Row %{row}: %{message}", { row: item.row, message: item.message })}
                      </List.Item>
                    ))}
                  </List>
                  {rowErrors.length > 50 && (
                    <Text as="p" variant="bodySm" tone="subdued">
                      {t("common.and_more", "and %{count} more", { count: rowErrors.length - 50 })}
                    </Text>
                  )}
                </BlockStack>
              )}
            </>
          ) : (
            <>
              <Text as="p">
                {t("shipping.import_help", "Columns: name, description, price, country, province, min_total, max_total. Prices and totals are plain amounts in your store currency. Country is a 2-letter code; province is the province code and may be empty.")}
              </Text>
              <InlineStack>
                <a href={templateHref} download="cod-form-shipping-rates.csv">
                  {t("shipping.import_template", "Download a sample file")}
                </a>
              </InlineStack>
              <DropZone
                accept=".csv,text/csv"
                type="file"
                allowMultiple={false}
                onDrop={(_files, accepted, rejectedFiles) => {
                  setRejected(rejectedFiles.length > 0 && accepted.length === 0);
                  if (accepted[0]) setFile(accepted[0]);
                }}
              >
                {file ? (
                  <div style={{ padding: 16 }}>
                    <Text as="p" variant="bodyMd" fontWeight="semibold">
                      {file.name}
                    </Text>
                    <Text as="p" variant="bodySm" tone="subdued">
                      {t("shipping.import_file_size", "%{size} KB", { size: Math.max(1, Math.round(file.size / 1024)) })}
                    </Text>
                  </div>
                ) : (
                  <DropZone.FileUpload actionTitle={t("shipping.import_choose", "Choose CSV file")} />
                )}
              </DropZone>
              {rejected && (
                <Banner tone="critical">
                  <p>{t("shipping.import_rejected", "That file is not a CSV file.")}</p>
                </Banner>
              )}
              <ChoiceList
                title={t("shipping.import_mode", "What to do with your current rates")}
                choices={[
                  { label: t("shipping.import_append", "Keep them and add the imported rates"), value: "append" },
                  { label: t("shipping.import_replace", "Replace them with the imported rates"), value: "replace" },
                ]}
                selected={[mode]}
                onChange={(value) => setMode(value[0])}
              />
              {mode === "replace" && (
                <Banner tone="warning">
                  <p>{t("shipping.import_replace_warning", "All your current rates are deleted when the import succeeds.")}</p>
                </Banner>
              )}
            </>
          )}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

export default CsvImportModal;
