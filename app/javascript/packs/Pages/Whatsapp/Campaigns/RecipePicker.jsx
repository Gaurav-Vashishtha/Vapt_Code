import React, { useEffect, useState } from "react";
import { Card, BlockStack, InlineStack, InlineGrid, Box, Text, Button, Badge, SkeletonBodyText } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { api } from "./api";
import { t, paths } from "./copy";

const recipeTitle = (r) => t(`recipe_${r.key}_title`, r.title);
const recipeDescription = (r) => t(`recipe_${r.key}_description`, r.description);
const recipeAudience = (r) => t(`recipe_${r.key}_audience`, r.audience_summary);

const statusBadge = (status) => {
  if (status === "approved") return <Badge tone="success">{t("recipe_message_ready", "Message ready")}</Badge>;
  if (status === "pending") return <Badge tone="attention">{t("recipe_message_waiting", "Waiting for approval")}</Badge>;
  return <Badge>{t("recipe_message_needed", "Message needs approval")}</Badge>;
};

const RecipePicker = ({ disabled = false, busyKey = null, onPick, onError }) => {
  const [recipes, setRecipes] = useState(null);

  useEffect(() => {
    let alive = true;
    api("/api/whatsapp/campaign_recipes")
      .then((data) => { if (alive) setRecipes(data.recipes || []); })
      .catch((e) => {
        if (!alive) return;
        setRecipes([]);
        onError?.(e.message);
      });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (recipes !== null && recipes.length === 0) return null;

  const pick = (key) => (onPick ? onPick(key) : navigateTo(paths.recipe(key)));

  return (
    <Card>
      <BlockStack gap="400">
        <BlockStack gap="050">
          <Text as="h2" variant="headingMd">{t("recipe_title", "Start from a ready-made campaign")}</Text>
          <Text as="p" variant="bodySm" tone="subdued">
            {t("recipe_help", "Each one comes with an audience and a message. You can change anything before sending.")}
          </Text>
        </BlockStack>
        {recipes === null ? (
          <SkeletonBodyText lines={3} />
        ) : (
          <InlineGrid columns={{ xs: 1, sm: 2, lg: 4 }} gap="300">
            {recipes.map((r) => (
              <Box key={r.key} background="bg-surface-secondary" padding="400" borderRadius="200">
                <BlockStack gap="300">
                  <BlockStack gap="100">
                    <Text as="h3" variant="headingSm">{recipeTitle(r)}</Text>
                    <Text as="p" variant="bodySm" tone="subdued">{recipeDescription(r)}</Text>
                    <Text as="p" variant="bodySm">
                      {t("recipe_audience_line", "To: %{audience}", { audience: recipeAudience(r) })}
                    </Text>
                  </BlockStack>
                  <InlineStack align="space-between" blockAlign="center" gap="200">
                    {statusBadge(r.template_status)}
                    <Button size="slim" onClick={() => pick(r.key)} disabled={disabled} loading={busyKey === r.key}>
                      {t("recipe_use", "Use this")}
                    </Button>
                  </InlineStack>
                </BlockStack>
              </Box>
            ))}
          </InlineGrid>
        )}
      </BlockStack>
    </Card>
  );
};

export default RecipePicker;
