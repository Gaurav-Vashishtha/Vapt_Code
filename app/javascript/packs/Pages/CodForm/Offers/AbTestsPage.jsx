import React, { useCallback, useEffect, useState } from "react";
import { Badge, BlockStack, Button, Card, Divider, InlineStack, Text } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { codFormApi, parseError } from "../api";
import Gate from "../components/Gate";
import Screen from "../components/Screen";
import EmptyState from "../components/EmptyState";
import { FEATURES, PATHS } from "../constants";
import { t } from "../i18n";
import { offerMeta, segmentForType } from "./offerMeta";

export const abStatusLabel = (status) => {
  switch (status) {
    case "running":
      return t("offers.ab_status_running", "Running");
    case "stopped":
      return t("offers.ab_status_stopped", "Stopped");
    default:
      return t("offers.status_draft", "Draft");
  }
};

/** /features/cod-form/offers/ab-tests — A/B tests on offers (OFF-12). */
const AbTestsPage = () => {
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);

  const load = useCallback(() => {
    setError(null);
    codFormApi.abTests
      .index()
      .then((response) => setItems((response && response.items) || []))
      .catch((err) => setError(parseError(err)));
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const newPath = `${PATHS.abTests}/new`;

  return (
    <Screen
      title={t("offers.ab_tests_title", "A/B tests")}
      subtitle={t("offers.ab_tests_desc", "Compare up to four versions of an offer and see which one earns more.")}
      backPath={PATHS.offers}
      backLabel={t("offers.title", "Offers")}
      primaryAction={{ content: t("offers.ab_new", "New A/B test"), onAction: () => navigateTo(newPath) }}
      loading={items === null && !error}
      error={error}
      onRetry={load}
    >
      <Gate feature={FEATURES.AB_TESTS} title={t("offers.ab_tests_title", "A/B tests")}>
        {items && items.length === 0 ? (
          <EmptyState
            heading={t("offers.ab_empty_title", "No A/B test yet")}
            action={{ content: t("offers.ab_new", "New A/B test"), onAction: () => navigateTo(newPath) }}
          >
            <p>{t("offers.ab_empty_body", "Create two or more offers of the same kind, then split your traffic between them.")}</p>
          </EmptyState>
        ) : (
          <Card>
            <BlockStack gap="300">
              {(items || []).map((test, index) => (
                <React.Fragment key={test.id}>
                  {index > 0 && <Divider />}
                  <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
                    <BlockStack gap="050">
                      <InlineStack gap="200" blockAlign="center" wrap>
                        <Text as="h3" variant="headingSm">
                          {test.name}
                        </Text>
                        <Badge tone={test.status === "running" ? "success" : undefined}>{abStatusLabel(test.status)}</Badge>
                      </InlineStack>
                      <Text as="span" variant="bodySm" tone="subdued">
                        {offerMeta(segmentForType(test.offer_type)).title} ·{" "}
                        {t("offers.ab_variants_count", "%{count} variants", { count: (test.variants || []).length })}
                      </Text>
                    </BlockStack>
                    <Button variant="primary" onClick={() => navigateTo(`${PATHS.abTests}/${test.id}`)}>
                      {test.status === "draft" ? t("common.edit", "Edit") : t("offers.ab_view", "View results")}
                    </Button>
                  </InlineStack>
                </React.Fragment>
              ))}
            </BlockStack>
          </Card>
        )}
      </Gate>
    </Screen>
  );
};

export default AbTestsPage;
