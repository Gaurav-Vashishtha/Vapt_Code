import React from "react";
import {
  Page,
  Banner,
  BlockStack,
  Card,
  Box,
  List,
  SkeletonBodyText,
  SkeletonDisplayText,
} from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { t } from "../i18n";
import { UpgradeCard } from "./Gate";
import StorefrontSyncBanner from "./StorefrontSyncBanner";

export const ScreenSkeleton = ({ cards = 3 }) => (
  <BlockStack gap="400">
    {Array.from({ length: cards }).map((_, index) => (
      <Card key={index}>
        <Box padding="200">
          <BlockStack gap="400">
            <SkeletonDisplayText size="small" />
            <SkeletonBodyText lines={3} />
          </BlockStack>
        </Box>
      </Card>
    ))}
  </BlockStack>
);

/** Banner for a failed load, with retry. */
export const LoadErrorBanner = ({ error, onRetry }) => {
  if (!error) return null;
  if (error.isGate) return <UpgradeCard feature={error.feature} minTier={error.minTier} />;
  return (
    <Banner
      tone="critical"
      title={t("common.load_error_title", "This page could not be loaded")}
      action={onRetry ? { content: t("common.retry", "Try again"), onAction: onRetry } : undefined}
    >
      <p>
        {error.isModuleDisabled
          ? t("common.module_disabled_body", "COD Form is not available for this store yet.")
          : t("common.load_error_body", "Check your connection and try again. If it keeps happening, contact support.")}
      </p>
    </Banner>
  );
};

/* Form and button validation come back as engine codes (invalid_color, required…),
   everything else as an English sentence. Codes are mapped; sentences pass through. */
const messageText = (message) => {
  switch (message) {
    case "required":
      return t("common.error_required", "is required");
    case "invalid":
      return t("common.error_invalid", "is not valid");
    case "invalid_color":
      return t("common.error_invalid_color", "is not a valid colour");
    case "invalid_url":
      return t("common.error_invalid_url", "is not a valid https link");
    case "invalid_regex":
      return t("common.error_invalid_regex", "is not a valid pattern");
    case "invalid_selector":
      return t("common.error_invalid_selector", "is not a valid CSS selector");
    case "too_long":
      return t("common.error_too_long", "is too long");
    case "too_many":
      return t("common.error_too_many", "has too many entries");
    case "out_of_range":
      return t("common.error_out_of_range", "is out of range");
    case "duplicate":
      return t("common.error_duplicate", "is used twice");
    case "unknown":
      return t("common.error_unknown", "is not recognised");
    default:
      return /^[a-z0-9_]+$/.test(message) ? message.replace(/_/g, " ") : message;
  }
};

/** Banner for a failed save: validation messages (422) or a gate (402). */
export const SaveErrorBanner = ({ error, onDismiss }) => {
  if (!error) return null;
  if (error.isGate) return <UpgradeCard feature={error.feature} minTier={error.minTier} />;
  return (
    <Banner
      tone="critical"
      title={
        error.isValidation
          ? t("common.validation_error_title", "Some settings need your attention")
          : t("common.save_error_title", "Your changes could not be saved")
      }
      onDismiss={onDismiss}
    >
      {error.messages && error.messages.length > 0 ? (
        <List type="bullet">
          {error.messages.slice(0, 8).map((item, index) => (
            <List.Item key={`${item.path}-${index}`}>
              {item.path && item.path !== "base" ? `${item.path}: ${messageText(item.message)}` : messageText(item.message)}
            </List.Item>
          ))}
        </List>
      ) : (
        <p>{t("common.save_error_body", "Try again. If it keeps happening, contact support.")}</p>
      )}
    </Banner>
  );
};

/**
 * Page frame of a COD Form screen: title, optional back link, loading
 * skeleton and load-error banner, then the screen's cards.
 */
const Screen = ({
  title,
  subtitle,
  backPath,
  backLabel,
  primaryAction,
  secondaryActions,
  titleMetadata,
  loading,
  error,
  onRetry,
  skeletonCards,
  children,
}) => (
  <Page
    fullWidth
    title={title}
    subtitle={subtitle}
    titleMetadata={titleMetadata}
    primaryAction={loading || error ? undefined : primaryAction}
    secondaryActions={loading || error ? undefined : secondaryActions}
    backAction={
      backPath
        ? { content: backLabel || t("common.back", "Back"), onAction: () => navigateTo(backPath) }
        : undefined
    }
  >
    <Box paddingBlockEnd="800">
      {loading ? (
        <ScreenSkeleton cards={skeletonCards} />
      ) : error ? (
        <LoadErrorBanner error={error} onRetry={onRetry} />
      ) : (
        <BlockStack gap="400">
          <StorefrontSyncBanner />
          {children}
        </BlockStack>
      )}
    </Box>
  </Page>
);

export default Screen;
