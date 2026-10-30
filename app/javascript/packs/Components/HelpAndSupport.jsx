import React from "react";
import {
  Page,
  Layout,
  Card,
  BlockStack,
  InlineStack,
  Box,
  Text,
  Button,
  List,
  Link,
  Icon,
  Divider,
} from "@shopify/polaris";
import { ChatMajor, EmailMajor } from "@shopify/polaris-icons";

import I18n from "../i18n-lang";
import CallbackRequest from "./CallbackRequest";
import FeatureCallout from "./FeatureCallout";

export default function HelpAndSupport() {
  const youtubeResources = [
    {
      title: I18n.t("support.pre_order_otp"),
      url: "https://www.youtube.com/watch?v=yCPBjrO2tFA",
    },
    {
      title: I18n.t("support.partial_payment"),
      url: "https://www.youtube.com/watch?v=BtB4CVRqwZM",
    },
    {
      title: I18n.t("support.cod_only_otp"),
      url: "https://www.youtube.com/watch?v=e3zYWQpMhlQ",
    },
    {
      title: I18n.t("support.cod_shopify_plus"),
      url: "https://www.youtube.com/watch?v=hebUv0sciBA",
    },
    {
      title: I18n.t("support.login_otp"),
      url: "https://www.youtube.com/watch?v=UghVNC3zTSc",
    },
    {
      title: I18n.t("support.cod_fees"),
      url: "https://www.youtube.com/watch?v=I22U3fj6vKo",
    },
  ];
  return (
    <Page
      fullWidth
      title={I18n.t("support.page_title")}
      subtitle={I18n.t("support.need_help_desc")}
    >
      <Layout>
        <Layout.Section>
          <FeatureCallout
            illustration="docs"
            title={I18n.t("support.need_help_title")}
            description={I18n.t("support.need_help_desc")}
            docsUrl="https://codking.tech/documentation/"
            showChat
          />
        </Layout.Section>

        {/* Contact Support Section */}
        <Layout.Section>
          <Card padding="500">
            <Box>
              <BlockStack gap="500">
                {/* The heading used to repeat here; the callout above carries
                    it now, so the card leads straight into the two options. */}
                <InlineStack gap="300" wrap={false}>
                  {/* Live Chat Option */}
                  <Box style={{ flex: 1 }}>
                    <Card background="bg-surface-secondary">
                      <Box padding="400">
                        <BlockStack gap="300" align="center">
                          <Box
                            padding="200"
                            background="bg-surface-success-subdued"
                            borderRadius="100"
                          >
                            <Icon source={ChatMajor} tone="success" />
                          </Box>
                          <BlockStack gap="100" align="center">
                            <Text
                              as="h3"
                              variant="headingSm"
                              alignment="center"
                            >
                              {I18n.t("support.chat")}
                            </Text>
                            <Text
                              as="p"
                              variant="bodySm"
                              tone="subdued"
                              alignment="center"
                            >
                              {I18n.t("support.chat_with_us_subtitle")}
                            </Text>
                          </BlockStack>
                          <Button
                            variant="primary"
                            size="medium"
                            fullWidth
                            onClick={() =>
                              window.$crisp?.push(["do", "chat:open"])
                            }
                          >
                            {I18n.t("support.start_chat")}
                          </Button>
                        </BlockStack>
                      </Box>
                    </Card>
                  </Box>
                  {/* Email Support */}
                  <Box style={{ flex: 1 }}>
                    <Card background="bg-surface-secondary">
                      <Box padding="400">
                        <BlockStack gap="300" align="center">
                          <Box
                            padding="200"
                            background="bg-surface-info-subdued"
                            borderRadius="100"
                          >
                            <Icon source={EmailMajor} tone="info" />
                          </Box>
                          <BlockStack gap="100" align="center">
                            <Text
                              as="h3"
                              variant="headingSm"
                              alignment="center"
                            >
                              {I18n.t("support.email")}
                            </Text>
                            <Text
                              as="p"
                              variant="bodySm"
                              tone="subdued"
                              alignment="center"
                            >
                              {I18n.t("support.email_subtitle")}
                            </Text>
                          </BlockStack>
                          <Button
                            variant="secondary"
                            size="medium"
                            fullWidth
                            url="mailto:support@notifiktech.com"
                            external
                          >
                            {I18n.t("support.email")}
                          </Button>
                        </BlockStack>
                      </Box>
                    </Card>
                  </Box>
                  {/* Schedule Callback */}
                  <Box style={{ flex: 1 }}>
                    <CallbackRequest />
                  </Box>
                </InlineStack>
              </BlockStack>
            </Box>
          </Card>
        </Layout.Section>
        {/* Resources section - split layout */}
        <Layout.Section>
          <InlineStack gap="400" align="start">
            {/* Video tutorials */}
            <Box style={{ flex: 1 }}>
              <Card>
                <BlockStack gap="400">
                  <Box padding="400" paddingBlockEnd="0">
                    <InlineStack gap="200" align="center">
                      <Text as="h3" variant="headingMd">
                        {I18n.t("support.videos_title")}
                      </Text>
                    </InlineStack>
                  </Box>
                  <Box padding="400" paddingBlockStart="0">
                    <BlockStack gap="200">
                      {youtubeResources.map((video, idx) => (
                        <Box
                          key={idx}
                          padding="200"
                          background="bg-surface-secondary"
                          borderRadius="200"
                        >
                          <Link url={video.url} external removeUnderline>
                            <Text as="p" variant="bodyMd">
                              {video.title}
                            </Text>
                          </Link>
                        </Box>
                      ))}
                    </BlockStack>
                  </Box>
                </BlockStack>
              </Card>
            </Box>
            {/* Documentation */}
            <Box style={{ flex: 1 }}>
              <Card>
                <BlockStack gap="400">
                  <Box padding="400" paddingBlockEnd="0">
                    <InlineStack gap="200" align="center">
                      <Text as="h3" variant="headingMd">
                        {I18n.t("support.docs_title")}
                      </Text>
                    </InlineStack>
                  </Box>
                  <Box padding="400" paddingBlockStart="0">
                    <Box
                      padding="400"
                      background="bg-surface-secondary"
                      borderRadius="200"
                    >
                      <Link
                        url="https://codking.tech/documentation/"
                        external
                        removeUnderline
                      >
                        <BlockStack gap="100">
                          <Text as="p" variant="bodyMd" fontWeight="medium">
                            {I18n.t("support.docs_link")}
                          </Text>
                          <Text as="p" variant="bodySm" tone="subdued">
                            {I18n.t("support.complete_documentation")}
                          </Text>
                        </BlockStack>
                      </Link>
                    </Box>
                  </Box>
                </BlockStack>
              </Card>
            </Box>
          </InlineStack>
        </Layout.Section>
      </Layout>
    </Page>
  );
}
