import React, { useState } from "react";
import { Banner, BlockStack, Button, Card, InlineStack, Text, TextField } from "@shopify/polaris";
import { ImportMinor } from "@shopify/polaris-icons";
import { errorMessage, t } from "../format";
import { aiApi } from "./api";

const KnowledgeTab = ({ form, update, limits }) => {
  const [importing, setImporting] = useState(false);
  const [notice, setNotice] = useState(null);
  const max = limits?.max_knowledge || 8000;

  const importPolicies = async () => {
    setImporting(true);
    setNotice(null);
    try {
      const data = await aiApi.importKnowledge();
      update({ knowledge: data.knowledge });
      setNotice({ tone: "success", text: t("ai.import_done", "Store policies added below. Review them, then save.") });
    } catch (e) {
      setNotice({ tone: "warning", text: errorMessage(e) });
    } finally {
      setImporting(false);
    }
  };

  return (
    <Card>
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center" gap="200">
          <BlockStack gap="100">
            <Text as="h3" variant="headingSm">
              {t("ai.knowledge_title", "Store knowledge")}
            </Text>
            <Text as="p" tone="subdued">
              {t(
                "ai.knowledge_body",
                "The AI answers store questions only from this text. Orders, products and carts are read live from Shopify, so you don't need to add them.",
              )}
            </Text>
          </BlockStack>
          <Button icon={ImportMinor} onClick={importPolicies} loading={importing}>
            {t("ai.import", "Import store policies")}
          </Button>
        </InlineStack>
        {notice && (
          <Banner tone={notice.tone} onDismiss={() => setNotice(null)}>
            {notice.text}
          </Banner>
        )}
        <TextField
          label={t("ai.knowledge_title", "Store knowledge")}
          labelHidden
          value={form.knowledge || ""}
          onChange={(value) => update({ knowledge: value })}
          multiline={16}
          maxLength={max}
          showCharacterCount
          autoComplete="off"
        />
        <Text as="p" tone="subdued" variant="bodySm">
          {t(
            "ai.knowledge_tips",
            "Tips: write delivery times per region, COD charges and limits, return window and how to start a return, and your support hours. Short, factual lines work best.",
          )}
        </Text>
      </BlockStack>
    </Card>
  );
};

export default KnowledgeTab;
