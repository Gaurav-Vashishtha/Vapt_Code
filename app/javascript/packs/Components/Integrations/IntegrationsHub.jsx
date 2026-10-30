import React, { useContext, useEffect, useState } from "react";
import {
  Page,
  Layout,
  Card,
  BlockStack,
  InlineStack,
  InlineGrid,
  Text,
  Badge,
} from "@shopify/polaris";
import styled from "styled-components";
import { StoreContext } from "../../Context/Store";
import I18n from "../../i18n-lang";
import FeatureCallout from "../FeatureCallout";
import Api from "../../Services/Api";
import useCodFormIntegrationCards from "../../Pages/CodForm/Integrations/hubCards";

/* A directory rather than a list of sidebar entries: one card per integration,
   the whole card being the way in. The sidebar has a single Integrations row,
   so this page is where a merchant finds out what is on offer. */

const CardLink = styled.a`
  display: flex;
  text-decoration: none;
  color: inherit;
  border-radius: var(--p-border-radius-300, 12px);

  /* Polaris 12 gives Card no class of its own, so the card is reached as the
     anchor's only child. Stretching it keeps a row of cards level whatever
     length their descriptions run to. */
  > * {
    flex: 1;
    min-width: 0;
    transition: box-shadow 150ms ease;
  }

  &:hover > * {
    box-shadow: var(--p-shadow-200, 0 3px 6px rgba(0, 0, 0, 0.12));
  }

  &:focus-visible {
    outline: var(--p-border-width-050, 2px) solid
      var(--p-color-border-focus, #005bd3);
    outline-offset: 2px;
  }
`;

/* Each tool's own logo, on a plain tile so a white PNG and a dark one both
   sit right. contain rather than cover: a cropped logo reads as the wrong
   logo. */
const LOGOS = {
  meta: "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/meta.webp?v=1789122947",
  googleAds:
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/images.jpg?v=1789122965",
  webhooks:
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/images.png?v=1789122959",
};

const Tile = styled.span`
  flex: 0 0 auto;
  width: 40px;
  height: 40px;
  border-radius: 10px;
  border: 1px solid var(--p-color-border-secondary, #e3e3e3);
  background: #ffffff;
  overflow: hidden;
  display: inline-flex;
  align-items: center;
  justify-content: center;

  img {
    width: 100%;
    height: 100%;
    object-fit: contain;
    display: block;
  }
`;

const Logo = ({ src, alt }) => (
  <Tile>
    <img src={src} alt={alt} loading="lazy" />
  </Tile>
);

const IntegrationsHub = () => {
  const {
    setting: [setting],
    shop: [shop],
    tab: [, setTab],
  } = useContext(StoreContext);

  const [webhooksLive, setWebhooksLive] = useState(false);
  // TikTok, form pixels, Google Sheets, Klaviyo, Omnisend, address autocomplete:
  // empty unless the COD Form module is on for this shop.
  const codFormCards = useCodFormIntegrationCards();

  useEffect(() => {
    if (!shop?.id) return undefined;
    let cancelled = false;
    Api.get("/api/webhooks/endpoints")
      .then((response) => {
        const list = response?.data?.endpoints || [];
        if (!cancelled) {
          setWebhooksLive(list.some((e) => e.enabled && e.lastReceivedAt));
        }
      })
      .catch(() => {
        if (!cancelled) setWebhooksLive(false);
      });
    return () => {
      cancelled = true;
    };
  }, [shop?.id]);

  const openIntegration = (event, path) => {
    // Let a modified click open a new tab, as the anchor would.
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    window.history.pushState({}, "", path);
    window.dispatchEvent(new PopStateEvent("popstate"));
    if (typeof setTab === "function") setTab(path);
  };

  const googleEnabled = !!(
    setting?.googleConversionId || setting?.googleConversionLabel
  );
  const pixelEnabled = !!(setting?.pixelId || setting?.pixelToken);

  const integrations = [
    {
      key: "meta",
      title: I18n.t("integrations.pixel.title", { defaultValue: "Meta Pixel" }),
      category:
        I18n.t("integrations.category_tracking", {
          defaultValue: "Conversion tracking",
        }),
      description:
        I18n.t("integrations.pixel.card_description", {
          defaultValue: "Send COD events to Meta via the Conversions API.",
        }),
      connected: pixelEnabled,
      href: "/integrations/pixel",
      mark: <Logo src={LOGOS.meta} alt="" />,
    },
    {
      key: "google-ads",
      title: I18n.t("integrations.google_ads.title", {
        defaultValue: "Google Ads",
      }),
      category:
        I18n.t("integrations.category_tracking", {
          defaultValue: "Conversion tracking",
        }),
      description:
        I18n.t("integrations.google_ads.card_description", {
          defaultValue: "Report COD conversions back to Google Ads.",
        }),
      connected: googleEnabled,
      href: "/integrations/google-ads",
      mark: <Logo src={LOGOS.googleAds} alt="" />,
    },
    {
      key: "webhooks",
      title: I18n.t("integrations.webhooks.title", {
        defaultValue: "Inbound webhooks",
      }),
      category: I18n.t("integrations.category_developer", {
        defaultValue: "Developer",
      }),
      description:
        I18n.t("integrations.webhooks.card_description", {
          defaultValue:
            "Let Shopflo or another checkout platform push abandoned carts into your reminders.",
        }),
      connected: webhooksLive,
      href: "/settings-hub/webhooks",
      mark: <Logo src={LOGOS.webhooks} alt="" />,
    },
  ];

  return (
    <Page
      title={I18n.t("integrations.title", { defaultValue: "Integrations" })}
      subtitle={I18n.t("integrations.subtitle", {
        defaultValue: "Connect COD King to your marketing and conversion tools.",
      })}
      fullWidth
    >
      <Layout>
        <Layout.Section>
          <BlockStack gap="400">
            <FeatureCallout
              illustration="docs"
              title={I18n.t("integrations.help_title", {
                defaultValue: "About integrations",
              })}
              description={I18n.t("integrations.help_description", {
                defaultValue:
                  "Connect conversion tracking tools to measure your COD campaigns.",
              })}
              docsUrl="https://codking.tech/documentation/"
              showChat
            />

            <InlineGrid columns={{ xs: 1, sm: 2, md: 3 }} gap="400">
              {[...integrations, ...codFormCards].map((item) => (
                <CardLink
                  key={item.key}
                  href={item.href}
                  onClick={(event) => openIntegration(event, item.href)}
                >
                  <Card padding="500">
                    <BlockStack gap="300">
                      <InlineStack gap="300" blockAlign="start" wrap={false}>
                        {item.mark}
                        <BlockStack gap="150">
                          <Text variant="headingSm" as="h3">
                            {item.title}
                          </Text>
                          <InlineStack gap="150" blockAlign="center" wrap>
                            <Badge>{item.category}</Badge>
                            {item.connected && (
                              <Badge tone="success">
                                {I18n.t("integrations.connected", {
                                  defaultValue: "Connected",
                                })}
                              </Badge>
                            )}
                          </InlineStack>
                        </BlockStack>
                      </InlineStack>

                      <Text variant="bodySm" tone="subdued" as="p">
                        {item.description}
                      </Text>
                    </BlockStack>
                  </Card>
                </CardLink>
              ))}
            </InlineGrid>
          </BlockStack>
        </Layout.Section>
      </Layout>
    </Page>
  );
};

export default IntegrationsHub;
