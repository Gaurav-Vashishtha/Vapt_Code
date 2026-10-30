import React from "react";
import { BlockStack, Box, Button, Icon, InlineStack, Link, Spinner, Text } from "@shopify/polaris";
import { CustomersMajor, LocationMajor, NoteMajor } from "@shopify/polaris-icons";
import { mediaUrl } from "./api";
import { formatFileSize, safeExternalUrl, t } from "./format";

const imageStyle = { display: "block", maxWidth: "100%", maxHeight: 260, borderRadius: 8, cursor: "zoom-in" };

const Unavailable = ({ state }) =>
  state === "pending" ? (
    <InlineStack gap="200" blockAlign="center">
      <Spinner size="small" />
      <Text as="span" variant="bodySm" tone="subdued">
        {t("thread.media_loading", "Loading media…")}
      </Text>
    </InlineStack>
  ) : (
    <Text as="span" variant="bodySm" tone="subdued">
      {t("thread.media_expired", "This file is no longer available")}
    </Text>
  );

const FileCard = ({ icon, title, subtitle, action }) => (
  <Box padding="200" background="bg-surface" borderRadius="200" borderWidth="025" borderColor="border">
    <InlineStack gap="200" blockAlign="center" wrap={false}>
      <Icon source={icon} tone="subdued" />
      <Box minWidth="0">
        <BlockStack gap="050">
          <Text as="span" variant="bodySm" fontWeight="medium" truncate>
            {title}
          </Text>
          {subtitle && (
            <Text as="span" variant="bodySm" tone="subdued">
              {subtitle}
            </Text>
          )}
        </BlockStack>
      </Box>
      {action}
    </InlineStack>
  </Box>
);

const LocationCard = ({ content }) => {
  const lat = content?.latitude;
  const lng = content?.longitude;
  const url = safeExternalUrl(content?.url) || (lat != null && lng != null ? `https://www.google.com/maps?q=${lat},${lng}` : null);
  return (
    <FileCard
      icon={LocationMajor}
      title={content?.name || t("thread.location", "Shared location")}
      subtitle={content?.address}
      action={
        url && (
          <Link url={url} external>
            {t("thread.open_map", "Open map")}
          </Link>
        )
      }
    />
  );
};

const ContactsCard = ({ content }) => (
  <BlockStack gap="100">
    {(content?.contacts || []).map((contact, i) => (
      <FileCard
        key={`${contact.name}-${i}`}
        icon={CustomersMajor}
        title={contact.name || t("thread.contact_card", "Contact card")}
        subtitle={(contact.phones || []).join(", ")}
      />
    ))}
  </BlockStack>
);

const MessageMedia = ({ message, onOpenImage }) => {
  const { kind, media, content } = message;
  if (kind === "location") return <LocationCard content={content} />;
  if (kind === "contacts") return <ContactsCard content={content} />;

  const url = mediaUrl(media?.url);
  if (!url) return <Unavailable state={media?.state} />;

  switch (kind) {
    case "image":
      return (
        <img
          src={url}
          alt={message.body || t("thread.image", "Image")}
          style={imageStyle}
          loading="lazy"
          onClick={() => onOpenImage && onOpenImage(url)}
        />
      );
    case "sticker":
      return <img src={url} alt={t("thread.sticker", "Sticker")} style={{ width: 120, height: 120 }} loading="lazy" />;
    case "video":
      return <video src={url} controls preload="metadata" style={{ display: "block", maxWidth: "100%", maxHeight: 280, borderRadius: 8 }} />;
    case "audio":
      return (
        <BlockStack gap="100">
          {content?.voice && (
            <Text as="span" variant="bodySm" tone="subdued">
              {t("thread.voice_message", "Voice message")}
            </Text>
          )}
          <audio src={url} controls preload="none" style={{ maxWidth: "100%" }} />
        </BlockStack>
      );
    case "document":
      return (
        <FileCard
          icon={NoteMajor}
          title={media?.file_name || t("thread.document", "Document")}
          subtitle={formatFileSize(media?.size)}
          action={
            <Button size="slim" url={url} external download={media?.file_name || true}>
              {t("thread.download", "Download")}
            </Button>
          }
        />
      );
    default:
      return null;
  }
};

export default MessageMedia;
