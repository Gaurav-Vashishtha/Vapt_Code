import React, { useEffect, useState } from "react";
import styled from "styled-components";
import { Badge, BlockStack, Button, Card, Icon, InlineGrid, InlineStack, Text } from "@shopify/polaris";
import { LockMinor } from "@shopify/polaris-icons";
import { navigateTo } from "../../../../utils/navigate";
import { codFormApi } from "../api";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { FEATURES, PATHS, tierName } from "../constants";
import { t } from "../i18n";
import Screen from "../components/Screen";
import { OFFER_SEGMENTS, offerMeta } from "./offerMeta";

const CardLink = styled.a`
  display: flex;
  text-decoration: none;
  color: inherit;
  border-radius: var(--p-border-radius-300, 12px);

  > * {
    flex: 1;
    min-width: 0;
    transition: box-shadow 150ms ease;
  }

  &:hover > * {
    box-shadow: var(--p-shadow-200, 0 3px 6px rgba(0, 0, 0, 0.12));
  }

  &:focus-visible {
    outline: 2px solid var(--p-color-border-focus, #005bd3);
    outline-offset: 2px;
  }
`;

/** /features/cod-form/offers — a directory of cards, one per kind of offer. */
const OffersPage = () => {
  const bootstrap = useCodFormBootstrap();
  const [counts, setCounts] = useState({});
  const gates = (bootstrap && bootstrap.gates) || {};
  const allowed = (feature) => !gates[feature] || gates[feature].allowed !== false;

  useEffect(() => {
    if (!bootstrap) return;
    OFFER_SEGMENTS.forEach((segment) => {
      const meta = offerMeta(segment);
      if (!allowed(meta.feature)) return;
      codFormApi.offers
        .index(meta.offerType)
        .then((response) => {
          const items = (response && response.items) || [];
          setCounts((current) => ({
            ...current,
            [segment]: { total: items.length, active: items.filter((offer) => offer.status === "active").length },
          }));
        })
        .catch(() => {});
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bootstrap]);

  const open = (event, path) => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    navigateTo(path);
  };

  const cards = [
    ...OFFER_SEGMENTS.map((segment) => {
      const meta = offerMeta(segment);
      return { key: segment, title: meta.title, description: meta.description, feature: meta.feature, path: `${PATHS.offers}/${segment}` };
    }),
    {
      key: "ab-tests",
      title: t("offers.ab_tests_title", "A/B tests"),
      description: t("offers.ab_tests_desc", "Compare up to four versions of an offer and see which one earns more."),
      feature: FEATURES.AB_TESTS,
      path: PATHS.abTests,
    },
  ];

  return (
    <Screen
      title={t("offers.title", "Offers")}
      subtitle={t("offers.subtitle", "Raise the value of each COD order with quantity offers, order bumps, upsells and more.")}
      loading={!bootstrap}
    >
      <InlineGrid columns={{ xs: 1, sm: 2, lg: 3 }} gap="400">
        {cards.map((card) => {
          const isAllowed = allowed(card.feature);
          const count = counts[card.key];
          return (
            <CardLink key={card.key} href={card.path} onClick={(event) => open(event, card.path)}>
              <Card padding="500">
                <BlockStack gap="300">
                  <InlineStack gap="200" blockAlign="center" wrap>
                    <Text as="h3" variant="headingSm">
                      {card.title}
                    </Text>
                    {!isAllowed && (
                      <InlineStack gap="100" blockAlign="center" wrap={false}>
                        <span style={{ display: "inline-flex" }}>
                          <Icon source={LockMinor} tone="subdued" />
                        </span>
                        <Badge tone="info">{tierName((gates[card.feature] && gates[card.feature].min_tier) || "pro")}</Badge>
                      </InlineStack>
                    )}
                    {isAllowed && count && count.active > 0 && (
                      <Badge tone="success">{t("offers.active_count", "%{count} active", { count: count.active })}</Badge>
                    )}
                  </InlineStack>
                  <Text as="p" variant="bodySm" tone="subdued">
                    {card.description}
                  </Text>
                </BlockStack>
              </Card>
            </CardLink>
          );
        })}
      </InlineGrid>

      <Card>
        <BlockStack gap="200">
          <Text as="h3" variant="headingSm">
            {t("offers.stacking_title", "How discounts combine")}
          </Text>
          <Text as="p" tone="subdued">
            {t("offers.stacking_body", "Discounts apply in this order: quantity offer, then downsell, then discount code. Whether a discount code combines with offers is set in Setup, under More options.")}
          </Text>
          <InlineStack>
            <Button onClick={() => navigateTo(PATHS.setup)}>{t("offers.stacking_cta", "Open Setup")}</Button>
          </InlineStack>
        </BlockStack>
      </Card>
    </Screen>
  );
};

export default OffersPage;
