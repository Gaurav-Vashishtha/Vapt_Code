import React, { useCallback, useEffect, useState } from "react";
import { Banner, BlockStack, Card, DataTable, InlineStack, Pagination, Select, SkeletonBodyText, Text } from "@shopify/polaris";
import { codFormApi, parseError } from "../api";
import { formatDateTime } from "../utils";
import { t } from "../i18n";
import { REASON_CODES, reasonLabel, stageLabel } from "./reasons";

/** Blocked-attempts log (FRD-6): every rejection with its reason. Values are masked by the server. */
const BlockedAttemptsTable = () => {
  const [page, setPage] = useState(1);
  const [reason, setReason] = useState("");
  const [state, setState] = useState({ items: null, meta: {} });
  const [error, setError] = useState(null);

  const load = useCallback(() => {
    setError(null);
    codFormApi.rejections
      .index({ page, reason })
      .then((response) => setState({ items: (response && response.items) || [], meta: (response && response.meta) || {} }))
      .catch((err) => setError(parseError(err)));
  }, [page, reason]);

  useEffect(() => {
    load();
  }, [load]);

  const { items, meta } = state;
  const pages = Number(meta.pages) || 1;

  return (
    <Card>
      <BlockStack gap="400">
        <InlineStack align="space-between" blockAlign="end" gap="300" wrap>
          <BlockStack gap="100">
            <Text as="h2" variant="headingMd">
              {t("fraud.attempts_title", "Blocked attempts")}
            </Text>
            <Text as="p" tone="subdued">
              {t("fraud.attempts_help", "Every time the form refused a COD order, and why.")}
            </Text>
          </BlockStack>
          <div style={{ minWidth: 220 }}>
            <Select
              label={t("fraud.attempts_filter", "Reason")}
              options={[
                { value: "", label: t("fraud.attempts_all", "All reasons") },
                ...REASON_CODES.map((code) => ({ value: code, label: reasonLabel(code) })),
              ]}
              value={reason}
              onChange={(value) => {
                setReason(value);
                setPage(1);
                setState({ items: null, meta: {} });
              }}
            />
          </div>
        </InlineStack>
        {error ? (
          <Banner tone="critical" action={{ content: t("common.retry", "Try again"), onAction: load }}>
            <p>{t("fraud.attempts_error", "The blocked attempts could not be loaded.")}</p>
          </Banner>
        ) : items === null ? (
          <SkeletonBodyText lines={4} />
        ) : items.length === 0 ? (
          <Text as="p" tone="subdued">
            {t("fraud.attempts_empty", "No blocked attempts yet.")}
          </Text>
        ) : (
          <DataTable
            columnContentTypes={["text", "text", "text", "text"]}
            headings={[
              t("fraud.attempts_col_time", "Time"),
              t("fraud.attempts_col_reason", "Reason"),
              t("fraud.attempts_col_subject", "Buyer"),
              t("fraud.attempts_col_stage", "Step"),
            ]}
            rows={items.map((item) => [
              formatDateTime(item.created_at),
              reasonLabel(item.reason_code),
              item.subject_masked || "—",
              stageLabel(item.stage),
            ])}
          />
        )}
        {pages > 1 && (
          <InlineStack align="center">
            <Pagination
              hasPrevious={page > 1}
              hasNext={page < pages}
              onPrevious={() => setPage(page - 1)}
              onNext={() => setPage(page + 1)}
              label={t("common.page_of", "Page %{page} of %{pages}", { page, pages })}
            />
          </InlineStack>
        )}
      </BlockStack>
    </Card>
  );
};

export default BlockedAttemptsTable;
