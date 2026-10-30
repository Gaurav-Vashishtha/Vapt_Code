import React, { useCallback, useEffect, useState } from "react";
import { Badge, Banner, BlockStack, Button, Card, Divider, InlineStack, Text } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { codFormApi, parseError } from "../api";
import Gate from "../components/Gate";
import Screen, { SaveErrorBanner } from "../components/Screen";
import EmptyState from "../components/EmptyState";
import { PATHS } from "../constants";
import { t } from "../i18n";
import { discountTypeLabel, offerMeta, statusLabel, statusTone } from "./offerMeta";

const targetingSummary = (targeting) => {
  const value = targeting || {};
  if (value.scope !== "selected") return t("common.all_products", "All products");
  return t("offers.targeting_summary", "%{products} products · %{collections} collections", {
    products: (value.product_ids || []).length,
    collections: (value.collection_ids || []).length,
  });
};

// "Cart has: … → Offer: …" for a pre-purchase upsell rule.
const ruleSummary = (offer) => {
  const config = offer.config || {};
  const offered =
    config.source === "collection"
      ? t("offers.pre_upsell_summary_collection", "a collection")
      : t("offers.pre_upsell_summary_products", "%{count} products", { count: (config.product_ids || []).length });
  const discount = discountTypeLabel(config.discount_type || "none");
  return t("offers.pre_upsell_summary", "Cart has: %{cart} → Offer: %{offered} · %{discount}", {
    cart: targetingSummary(offer.targeting),
    offered,
    discount,
  });
};

/** /features/cod-form/offers/:type — offers of one kind with activate / pause, edit. */
const OffersListPage = ({ segment }) => {
  const meta = offerMeta(segment);
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [busy, setBusy] = useState(null);

  const load = useCallback(() => {
    setError(null);
    return codFormApi.offers
      .index(meta.offerType)
      .then((response) => {
        const list = ((response && response.items) || [])
          .filter((offer) => offer.status !== "archived")
          .sort((a, b) => (a.priority || 0) - (b.priority || 0));
        setItems(list);
      })
      .catch((err) => setError(parseError(err)));
  }, [meta.offerType]);

  useEffect(() => {
    setItems(null);
    load();
  }, [load]);

  const activeCount = (items || []).filter((offer) => offer.status === "active").length;
  const atLimit = meta.activeLimit != null && activeCount >= meta.activeLimit;

  const setStatus = (offer, status) => {
    setBusy(offer.id);
    setActionError(null);
    codFormApi.offers
      .status(offer.id, status)
      .then(() => load())
      .catch((err) => setActionError(parseError(err)))
      .then(() => setBusy(null));
  };

  const newPath = `${PATHS.offers}/${segment}/new`;

  return (
    <Screen
      title={meta.title}
      subtitle={meta.description}
      backPath={PATHS.offers}
      backLabel={t("offers.title", "Offers")}
      primaryAction={{ content: meta.newLabel, onAction: () => navigateTo(newPath) }}
      loading={items === null && !error}
      error={error}
      onRetry={load}
    >
      <Gate feature={meta.feature} title={meta.title}>
        <SaveErrorBanner error={actionError} onDismiss={() => setActionError(null)} />
        {atLimit && meta.limitText && (
          <Banner tone="info">
            <p>{meta.limitText}</p>
          </Banner>
        )}
        {items && items.length === 0 ? (
          <EmptyState heading={meta.title} action={{ content: meta.newLabel, onAction: () => navigateTo(newPath) }}>
            <p>{meta.description}</p>
          </EmptyState>
        ) : (
          <Card>
            <BlockStack gap="300">
              {(items || []).map((offer, index) => (
                <React.Fragment key={offer.id}>
                  {index > 0 && <Divider />}
                  <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
                    <BlockStack gap="050">
                      <InlineStack gap="200" blockAlign="center" wrap>
                        <Text as="h3" variant="headingSm">
                          {offer.name}
                        </Text>
                        <Badge tone={statusTone(offer.status)}>{statusLabel(offer.status)}</Badge>
                        {offer.ab_test_id && <Badge tone="info">{t("offers.in_test_badge", "In A/B test")}</Badge>}
                      </InlineStack>
                      <Text as="span" variant="bodySm" tone="subdued">
                        {offer.offer_type === "pre_upsell"
                          ? ruleSummary(offer)
                          : offer.offer_type === "bundle"
                          ? t("offers.bundle_summary", "%{count} products · %{discount}", {
                              count: ((offer.config || {}).product_ids || []).length,
                              discount: discountTypeLabel((offer.config || {}).discount_type || "none"),
                            })
                          : targetingSummary(offer.targeting)}
                      </Text>
                    </BlockStack>
                    <InlineStack gap="200" wrap>
                      {offer.status === "active" ? (
                        <Button loading={busy === offer.id} onClick={() => setStatus(offer, "paused")}>
                          {t("offers.pause", "Pause")}
                        </Button>
                      ) : (
                        <Button loading={busy === offer.id} disabled={atLimit} onClick={() => setStatus(offer, "active")}>
                          {t("offers.activate", "Activate")}
                        </Button>
                      )}
                      <Button variant="primary" onClick={() => navigateTo(`${PATHS.offers}/${segment}/${offer.id}`)}>
                        {t("common.edit", "Edit")}
                      </Button>
                    </InlineStack>
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

export default OffersListPage;
