import React, { useCallback, useContext, useEffect, useState } from "react";
import {
  Page,
  Layout,
  Card,
  Box,
  Text,
  BlockStack,
  InlineStack,
  Badge,
  Button,
  Popover,
  ActionList,
  IndexTable,
  useIndexResourceState,
} from "@shopify/polaris";
import { HorizontalDotsMinor } from "@shopify/polaris-icons";
import { useAppBridge } from "@shopify/app-bridge-react";
import { StoreContext } from "../../Context/Store";
import Api from "../../Services/Api";
import DiscountForm from "./DiscountForm";
import FeatureCallout from "../FeatureCallout";
import I18n from "../../i18n-lang";

// Mirrors Shopify's native discounts index status column.
function statusBadge(d) {
  if (d.syncStatus === "failed")
    return <Badge tone="critical">{I18n.t("discounts_page.failed")}</Badge>;
  if (d.syncStatus === "pending")
    return <Badge tone="attention" progress="incomplete">{I18n.t("discounts_page.syncing")}</Badge>;
  if (!d.isActive)
    return <Badge tone="info" progress="incomplete">{I18n.t("discounts_page.inactive")}</Badge>;
  return <Badge tone="success" progress="complete">{I18n.t("discounts_page.active")}</Badge>;
}

function typeLabel(d) {
  if (d.discountType === "buy_x_get_y") return "Buy X get Y";
  if (d.discountType === "percentage") return `${d.value}% off`;
  return `${d.value} off`;
}

function usedLabel(d) {
  if (d.method !== "code") return "—";
  if (d.usageLimit == null || d.usageLimit === "") return "No limit";
  return `0 / ${d.usageLimit} used`;
}

export default function DiscountsPage() {
  const shopify = useAppBridge();
  useContext(StoreContext); // ensures provider mounted

  const [discounts, setDiscounts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [view, setView] = useState("list"); // 'list' | 'form'
  const [editing, setEditing] = useState(null);
  const [bulkOpen, setBulkOpen] = useState(false); // overflow menu in the top bulk bar

  const fetchDiscounts = useCallback(() => {
    setLoading(true);
    return Api.get("/discounts")
      .then((res) => setDiscounts(Array.isArray(res.data) ? res.data : []))
      .catch(() => setDiscounts([]))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    fetchDiscounts();
  }, [fetchDiscounts]);

  // Poll while anything is still syncing so the badge flips without a manual refresh.
  useEffect(() => {
    if (!discounts.some((d) => d.syncStatus === "pending")) return undefined;
    const t = setTimeout(fetchDiscounts, 4000);
    return () => clearTimeout(t);
  }, [discounts, fetchDiscounts]);

  const openCreate = useCallback(() => {
    setEditing(null);
    setView("form");
  }, []);

  const openEdit = useCallback((d) => {
    setEditing(d);
    setView("form");
  }, []);

  const handleSaved = useCallback(() => {
    setView("list");
    setEditing(null);
    fetchDiscounts();
  }, [fetchDiscounts]);

  const resourceName = { singular: "discount", plural: "discounts" };
  const { selectedResources, allResourcesSelected, handleSelectionChange, clearSelection } =
    useIndexResourceState(discounts, {
      resourceIDResolver: (d) => String(d.id),
    });
  const selectedCount = allResourcesSelected
    ? discounts.length
    : selectedResources.length;

  const runBulk = useCallback(
    async (path, verb) => {
      const chosen = discounts.filter((d) =>
        selectedResources.includes(String(d.id)),
      );
      try {
        await Promise.all(chosen.map((d) => Api.post(`/discounts/${d.id}/${path}`)));
        shopify?.toast?.show(`${chosen.length} ${chosen.length === 1 ? "discount" : "discounts"} ${verb}`);
      } catch (e) {
        shopify?.toast?.show(`Failed to ${verb} some discounts`, { isError: true });
      } finally {
        clearSelection();
        fetchDiscounts();
      }
    },
    [discounts, selectedResources, shopify, clearSelection, fetchDiscounts],
  );

  const handleBulkDelete = useCallback(async () => {
    const chosen = discounts.filter((d) =>
      selectedResources.includes(String(d.id)),
    );
    try {
      await Promise.all(chosen.map((d) => Api.delete(`/discounts/${d.id}`)));
      shopify?.toast?.show(`${chosen.length} ${chosen.length === 1 ? "discount" : "discounts"} deleted`);
    } catch (e) {
      shopify?.toast?.show("Failed to delete some discounts", { isError: true });
    } finally {
      clearSelection();
      fetchDiscounts();
    }
  }, [discounts, selectedResources, shopify, clearSelection, fetchDiscounts]);

  if (view === "form") {
    return (
      <DiscountForm
        discount={editing}
        onBack={() => setView("list")}
        onSaved={handleSaved}
      />
    );
  }

  return (
    <Page
      title={I18n.t("discounts_page.discounts")}
      subtitle={I18n.t("discounts_page.create_coupon_and_automatic_discounts_shown")}
      primaryAction={{ content: I18n.t("discounts_page.create_discount"), onAction: openCreate }}
      fullWidth={true}
    >
      <Layout>
        <Layout.Section>
          <Box paddingBlockEnd="400">
            <FeatureCallout
              illustration="discount"
              title={I18n.t("discounts_page.discounts")}
              description={I18n.t("discounts_page.create_coupon_and_automatic_discounts_shown")}
              docsUrl="https://codking.tech/documentation/"
              showChat
            />
          </Box>
          <Card padding="0">
            {selectedCount > 0 && (
              <Box
                background="bg-surface-secondary"
                paddingBlock="200"
                paddingInline="300"
                borderBlockEndWidth="025"
                borderColor="border"
              >
                <InlineStack gap="200" blockAlign="center">
                  <Button variant="tertiary" onClick={clearSelection}>
                    {`${selectedCount} selected`}
                  </Button>
                  <Button
                    variant="tertiary"
                    onClick={() => runBulk("activate", "activated")}
                  >
                    {I18n.t("discounts_page.activate_discounts")}
                  </Button>
                  <Button
                    variant="tertiary"
                    onClick={() => runBulk("deactivate", "deactivated")}
                  >
                    {I18n.t("discounts_page.deactivate_discounts")}
                  </Button>
                  <Popover
                    active={bulkOpen}
                    onClose={() => setBulkOpen(false)}
                    activator={
                      <Button
                        variant="tertiary"
                        icon={HorizontalDotsMinor}
                        accessibilityLabel={I18n.t("discounts_page.more_actions")}
                        onClick={() => setBulkOpen((o) => !o)}
                      />
                    }
                  >
                    <ActionList
                      actionRole="menuitem"
                      items={[
                        {
                          content: I18n.t("discounts_page.delete"),
                          destructive: true,
                          onAction: () => {
                            setBulkOpen(false);
                            handleBulkDelete();
                          },
                        },
                      ]}
                    />
                  </Popover>
                </InlineStack>
              </Box>
            )}
            <IndexTable
              resourceName={resourceName}
              itemCount={discounts.length}
              loading={loading}
              selectedItemsCount={
                allResourcesSelected ? "All" : selectedResources.length
              }
              onSelectionChange={handleSelectionChange}
              headings={[
                { title: I18n.t("discounts_page.discount") },
                { title: I18n.t("discounts_page.status") },
                { title: I18n.t("discounts_page.method") },
                { title: I18n.t("discounts_page.type") },
                { title: I18n.t("discounts_page.used") },
              ]}
              emptyState={
                <Box padding="600">
                  <Text as="p" tone="subdued" alignment="center">
                    {I18n.t("discounts_page.no_discounts_yet")}
                  </Text>
                </Box>
              }
            >
              {discounts.map((d, index) => (
                <IndexTable.Row
                  id={String(d.id)}
                  key={d.id}
                  position={index}
                  selected={selectedResources.includes(String(d.id))}
                  onClick={() => openEdit(d)}
                >
                  <IndexTable.Cell>
                    <BlockStack gap="050">
                      <Text variant="bodyMd" fontWeight="semibold" as="span">
                        {d.code || d.title}
                      </Text>
                      {d.code && d.title && d.title !== d.code && (
                        <Text variant="bodySm" tone="subdued" as="span">
                          {d.title}
                        </Text>
                      )}
                      {d.syncStatus === "failed" && d.syncError && (
                        <Text variant="bodySm" tone="critical" as="span">
                          {d.syncError}
                        </Text>
                      )}
                    </BlockStack>
                  </IndexTable.Cell>
                  <IndexTable.Cell>{statusBadge(d)}</IndexTable.Cell>
                  <IndexTable.Cell>
                    {d.method === "code" ? "Code" : "Automatic"}
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    <Text as="span" variant="bodyMd">
                      {typeLabel(d)}
                      {d.minimumRequirementType === "subtotal" &&
                        ` · min spend ${d.minimumRequirementValue}`}
                      {d.minimumRequirementType === "quantity" &&
                        ` · min ${d.minimumRequirementValue} items`}
                    </Text>
                  </IndexTable.Cell>
                  <IndexTable.Cell>{usedLabel(d)}</IndexTable.Cell>
                </IndexTable.Row>
              ))}
            </IndexTable>
          </Card>
        </Layout.Section>

        {/* <Layout.Section secondary>
          <Card>
            <Box padding="600">
              <BlockStack gap="300">
                <Text variant="headingSm" as="h3">
                  How it works
                </Text>
                <Text variant="bodySm" tone="subdued" as="p">
                  Discounts you create here are created as real native Shopify discounts
                  (no app/function), then shown as coupons on the COD widget. Customers
                  apply codes in the cart; automatic discounts apply themselves.
                </Text>
              </BlockStack>
            </Box>
          </Card>
        </Layout.Section> */}
      </Layout>
    </Page>
  );
}
