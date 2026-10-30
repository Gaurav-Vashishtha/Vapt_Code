/**
 * DocumentationCard Component
 *
 * A flexible, multi-card documentation component that can display various types of help and support cards.
 *
 * USAGE EXAMPLES:
 *
 * 1. Show only main documentation card (default):
 *    <DocumentationCard />
 *
 * 2. Show video tutorial with embedded YouTube:
 *    <DocumentationCard
 *      showVideoTutorial={true}
 *      videoUrl="https://youtu.be/VIDEO_ID"
 *      videoTitle="Setup Guide"
 *      videoSubtitle="Learn how to configure features"
 *    />
 *
 * 3. Show chat support:
 *    <DocumentationCard
 *      showChatSupport={true}
 *      chatTitle="Live Support"
 *      chatSubtitle="Get help from our team"
 *    />
 *
 * 4. Show feature-specific documentation:
 *    <DocumentationCard
 *      showFeatureDocs={true}
 *      featureDocsTitle="OTP Configuration"
 *      featureDocsSubtitle="Step-by-step OTP setup guide"
 *      featureDocsUrl="https://docs.example.com/otp"
 *      featureDocsButtonText="View OTP Guide"
 *    />
 *
 * 5. Show all cards (complete help center):
 *    <DocumentationCard
 *      showMainDocs={true}
 *      showVideoTutorial={true}
 *      showFeatureDocs={true}
 *      showChatSupport={true}
 *      videoUrl="https://youtu.be/VIDEO_ID"
 *      featureDocsUrl="https://docs.example.com/features"
 *    />
 *
 * 6. Show both video cards:
 *    <DocumentationCard
 *      showVideoTutorial={true}
 *      showSecondVideo={true}
 *      videoUrl="https://youtu.be/BASIC_TUTORIAL"
 *      secondVideoUrl="https://youtu.be/ADVANCED_TUTORIAL"
 *      videoTitle="Basic Setup"
 *      secondVideoTitle="Advanced Configuration"
 *    />
 *
 * 7. Hide main docs, show only video and chat:
 *    <DocumentationCard
 *      showMainDocs={false}
 *      showVideoTutorial={true}
 *      showChatSupport={true}
 *      videoUrl="https://youtu.be/VIDEO_ID"
 *    />
 *
 * PROPS REFERENCE:
 *
 * Main Documentation Card:
 * - showMainDocs: boolean (default: true) - Enable/disable main documentation card
 * - title: string - Card title (default: I18n.t("admin.need_help"))
 * - description: string - Card description (default: I18n.t("admin.check_docs"))
 * - buttonText: string - Button text (default: I18n.t("admin.view_documentation"))
 * - documentationUrl: string - Documentation URL (default: "https://codking.tech/documentation/")
 * - icon: Icon component - Card icon (default: SettingsMajor)
 * - iconTone: string - Icon tone (default: "base")
 * - buttonVariant: string - Button variant (default: "primary")
 * - showIcon: boolean - Show/hide icon (default: true)
 *
 * Video Tutorial Card:
 * - showVideoTutorial: boolean (default: false) - Enable/disable video card
 * - videoTitle: string - Video card title (default: "Video Tutorial")
 * - videoSubtitle: string - Video card subtitle (default: "Watch our step-by-step guide")
 * - videoUrl: string - YouTube URL (supports watch, youtu.be, embed formats)
 * - videoButtonText: string - Video button text (default: "Watch Video")
 *
 * Second Video Tutorial Card:
 * - showSecondVideo: boolean (default: false) - Enable/disable second video card
 * - secondVideoTitle: string - Second video card title (default: "Advanced Tutorial")
 * - secondVideoSubtitle: string - Second video card subtitle (default: "Learn advanced configurations")
 * - secondVideoUrl: string - Second YouTube URL (supports watch, youtu.be, embed formats)
 *
 * Feature Documentation Card:
 * - showFeatureDocs: boolean (default: false) - Enable/disable feature docs card
 * - featureDocsTitle: string - Feature docs title (default: "Feature Documentation")
 * - featureDocsSubtitle: string - Feature docs subtitle (default: "Learn about specific features")
 * - featureDocsUrl: string - Feature documentation URL
 * - featureDocsButtonText: string - Feature docs button text (default: "View Feature Docs")
 * - featureDocsIcon: Icon component - Feature docs icon (default: SettingsMajor)
 *
 * Chat Support Card:
 * - showChatSupport: boolean (default: false) - Enable/disable chat card
 * - chatTitle: string - Chat card title (default: I18n.t("admin.chat_with_us"))
 * - chatSubtitle: string - Chat card subtitle (default: I18n.t("admin.chat_with_us_subtitle"))
 * - liveSupportText: string - Live support text (default: I18n.t("admin.live_support_available"))
 * - responseTimeText: string - Response time text (default: I18n.t("admin.average_response_time"))
 * - chatButtonText: string - Chat button text (default: I18n.t("admin.start_chat"))
 *
 * Styling:
 * - fullWidth: boolean - Button full width (default: true)
 * - customStyles: object - Custom styles for main card
 *
 * CARD ORDER (when enabled):
 * 1. Main Documentation Card
 * 2. Video Tutorial Card
 * 3. Second Video Tutorial Card (if enabled)
 * 4. Feature Documentation Card
 * 5. Chat Support Card
 *
 * YOUTUBE URL FORMATS SUPPORTED:
 * - https://www.youtube.com/watch?v=VIDEO_ID
 * - https://youtu.be/VIDEO_ID
 * - https://www.youtube.com/embed/VIDEO_ID
 * - https://youtu.be/VIDEO_ID?si=SHARE_ID (with share parameters)
 */

import React, { useState, useCallback, useEffect } from "react";
import {
  Card,
  BlockStack,
  InlineGrid,
  Text,
  Button,
  Icon,
  Box,
  Modal,
} from "@shopify/polaris";
import { SettingsMajor, PlayMajor } from "@shopify/polaris-icons";
import I18n from "../i18n-lang";

const DocumentationCard = ({
  title = I18n.t("admin.need_help"),
  description = I18n.t("admin.check_docs"),
  buttonText = I18n.t("admin.view_documentation"),
  documentationUrl = "https://codking.tech/documentation/",
  icon = SettingsMajor,
  iconTone = "base",
  buttonVariant = "primary",
  fullWidth = true,
  showIcon = true,
  customStyles = {},
  showChatSupport = false,
  chatTitle = I18n.t("admin.chat_with_us"),
  chatSubtitle = I18n.t("admin.chat_with_us_subtitle"),
  liveSupportText = I18n.t("admin.live_support_available"),
  responseTimeText = I18n.t("admin.average_response_time"),
  chatButtonText = I18n.t("admin.start_chat"),
  showVideoTutorial = false,
  videoTitle = I18n.t("documentation.video_tutorial"),
  videoSubtitle = I18n.t("documentation.video_subtitle"),
  videoUrl = "",
  videoButtonText = I18n.t("documentation.watch_video"),
  showFeatureDocs = false,
  featureDocsTitle = I18n.t("documentation.feature_docs"),
  featureDocsSubtitle = I18n.t("documentation.feature_docs_subtitle"),
  featureDocsUrl = "",
  featureDocsButtonText = I18n.t("documentation.view_feature_docs"),
  featureDocsIcon = SettingsMajor,
  showMainDocs = true,
  showSecondVideo = false,
  secondVideoTitle = I18n.t("documentation.advanced_tutorial"),
  secondVideoSubtitle = I18n.t("documentation.advanced_tutorial_subtitle"),
  secondVideoUrl = "",
}) => {
  const [isVideoModalOpen, setIsVideoModalOpen] = useState(false);
  const [activeVideoUrl, setActiveVideoUrl] = useState("");
  const [activeVideoTitle, setActiveVideoTitle] = useState("");
  const handleDocumentationClick = () => {
    window.open(documentationUrl, "_blank");
  };

  const handleChatClick = () => {
    window.$crisp?.push(["do", "chat:open"]);
  };

  const handleFeatureDocsClick = () => {
    if (featureDocsUrl) {
      window.open(featureDocsUrl, "_blank");
    }
  };

  const handleVideoClick = (url, title) => {
    setActiveVideoUrl(url);
    setActiveVideoTitle(title);
    setIsVideoModalOpen(true);
  };

  const handleCloseVideoModal = () => {
    setIsVideoModalOpen(false);
    setActiveVideoUrl("");
    setActiveVideoTitle("");
  };

  // Handle Esc key press to close modal
  const handleKeyDown = useCallback(
    (event) => {
      if (event.key === "Escape" && isVideoModalOpen) {
        handleCloseVideoModal();
      }
    },
    [isVideoModalOpen]
  );

  // Add event listener for Esc key
  useEffect(() => {
    if (isVideoModalOpen) {
      document.addEventListener("keydown", handleKeyDown);
      // Prevent body scroll when modal is open
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "unset";
    }

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "unset";
    };
  }, [isVideoModalOpen, handleKeyDown]);

  const getEmbedUrl = (url) => {
    if (!url) return "";

    // Handle different YouTube URL formats
    const regExp =
      /^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|&v=)([^#&?]*).*/;
    const match = url.match(regExp);

    if (match && match[2].length === 11) {
      return `https://www.youtube.com/embed/${match[2]}`;
    }

    // If it's already an embed URL, return as is
    if (url.includes("youtube.com/embed/")) {
      return url;
    }

    // Fallback: try to extract video ID from various formats
    const videoIdMatch = url.match(
      /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([^&\n?#]+)/
    );
    if (videoIdMatch) {
      return `https://www.youtube.com/embed/${videoIdMatch[1]}`;
    }

    return url; // Return original URL if we can't parse it
  };

  const getThumbnailUrl = (url) => {
    if (!url) return "";

    // Extract video ID from various YouTube URL formats
    const videoIdMatch = url.match(
      /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([^&\n?#]+)/
    );

    if (videoIdMatch && videoIdMatch[1]) {
      return `https://img.youtube.com/vi/${videoIdMatch[1]}/maxresdefault.jpg`;
    }

    return "";
  };

  const renderContent = () => {
    if (
      showChatSupport ||
      showVideoTutorial ||
      showFeatureDocs ||
      showMainDocs ||
      showSecondVideo
    ) {
      const cards = [];

      // Main Documentation Card
      if (showMainDocs) {
        cards.push(
          <Card key="documentation" style={customStyles}>
            <BlockStack gap="300">
              {showIcon && (
                <InlineGrid columns="auto 1fr" gap="200" alignItems="center">
                  <Icon source={icon} tone={iconTone} />
                  <Text variant="headingMd" as="h3">
                    {title}
                  </Text>
                </InlineGrid>
              )}

              {!showIcon && (
                <Text variant="headingMd" as="h3">
                  {title}
                </Text>
              )}

              <Text variant="bodySm" tone="subdued">
                {description}
              </Text>

              <Button
                variant={buttonVariant}
                fullWidth={fullWidth}
                onClick={handleDocumentationClick}
              >
                {buttonText}
              </Button>
            </BlockStack>
          </Card>
        );
      }

      // Video Tutorial Card
      if (showVideoTutorial) {
        cards.push(
          <Card key="video">
            <BlockStack gap="400">
              <BlockStack gap="200">
                <Text variant="headingMd" as="h3">
                  {videoTitle}
                </Text>
                <Text variant="bodySm" tone="subdued">
                  {videoSubtitle}
                </Text>
              </BlockStack>

              {videoUrl ? (
                <Box
                  style={{
                    position: "relative",
                    paddingBottom: "56.25%", // 16:9 aspect ratio
                    height: 0,
                    overflow: "hidden",
                    borderRadius: "8px",
                    border: "1px solid #E1E3E5",
                    cursor: "pointer",
                    backgroundColor: "#f6f6f7",
                  }}
                  onClick={() => handleVideoClick(videoUrl, videoTitle)}
                >
                  {/* YouTube Thumbnail */}
                  <img
                    src={getThumbnailUrl(videoUrl)}
                    alt={videoTitle}
                    style={{
                      position: "absolute",
                      top: 0,
                      left: 0,
                      width: "100%",
                      height: "100%",
                      objectFit: "cover",
                      borderRadius: "8px",
                    }}
                    onError={(e) => {
                      e.target.style.display = "none";
                    }}
                  />

                  {/* Play Button Overlay */}
                  <Box
                    style={{
                      position: "absolute",
                      top: 0,
                      left: 0,
                      width: "100%",
                      height: "100%",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      background:
                        "linear-gradient(rgba(0,0,0,0.2), rgba(0,0,0,0.2))",
                      borderRadius: "8px",
                      transition: "background 0.2s ease",
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.background =
                        "linear-gradient(rgba(0,0,0,0.4), rgba(0,0,0,0.4))";
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.background =
                        "linear-gradient(rgba(0,0,0,0.2), rgba(0,0,0,0.2))";
                    }}
                  >
                    <Box
                      style={{
                        width: "80px",
                        height: "80px",
                        borderRadius: "50%",
                        backgroundColor: "rgba(0,0,0,0.8)",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        border: "3px solid white",
                        boxShadow: "0 4px 12px rgba(0,0,0,0.3)",
                      }}
                    >
                      <Icon
                        source={PlayMajor}
                        tone="base"
                        style={{
                          fontSize: "32px",
                          color: "white",
                          marginLeft: "4px", // Slight offset to center the play icon
                        }}
                      />
                    </Box>
                  </Box>

                  {/* Video Title Overlay */}
                  <Text
                    variant="bodyMd"
                    style={{
                      position: "absolute",
                      bottom: "16px",
                      left: "16px",
                      right: "16px",
                      color: "white",
                      textShadow: "0 1px 3px rgba(0,0,0,0.8)",
                      fontWeight: "500",
                      backgroundColor: "rgba(0,0,0,0.6)",
                      padding: "8px 12px",
                      borderRadius: "4px",
                      backdropFilter: "blur(4px)",
                    }}
                  >
                    {videoTitle}
                  </Text>
                </Box>
              ) : (
                <Box
                  padding="400"
                  background="bg-surface-subdued"
                  borderRadius="200"
                  style={{
                    textAlign: "center",
                    border: "1px solid #E1E3E5",
                  }}
                >
                  <Text variant="bodySm" tone="subdued">
                    {I18n.t("documentation.video_url_missing")}
                  </Text>
                </Box>
              )}
            </BlockStack>
          </Card>
        );
      }

      // Second Video Tutorial Card
      if (showSecondVideo) {
        cards.push(
          <Card key="second-video">
            <BlockStack gap="400">
              <BlockStack gap="200">
                <Text variant="headingMd" as="h3">
                  {secondVideoTitle}
                </Text>
                <Text variant="bodySm" tone="subdued">
                  {secondVideoSubtitle}
                </Text>
              </BlockStack>

              {secondVideoUrl ? (
                <Box
                  style={{
                    position: "relative",
                    paddingBottom: "56.25%", // 16:9 aspect ratio
                    height: 0,
                    overflow: "hidden",
                    borderRadius: "8px",
                    border: "1px solid #E1E3E5",
                    cursor: "pointer",
                    backgroundColor: "#f6f6f7",
                  }}
                  onClick={() =>
                    handleVideoClick(secondVideoUrl, secondVideoTitle)
                  }
                >
                  {/* YouTube Thumbnail */}
                  <img
                    src={getThumbnailUrl(secondVideoUrl)}
                    alt={secondVideoTitle}
                    style={{
                      position: "absolute",
                      top: 0,
                      left: 0,
                      width: "100%",
                      height: "100%",
                      objectFit: "cover",
                      borderRadius: "8px",
                    }}
                    onError={(e) => {
                      e.target.style.display = "none";
                    }}
                  />

                  {/* Play Button Overlay */}
                  <Box
                    style={{
                      position: "absolute",
                      top: 0,
                      left: 0,
                      width: "100%",
                      height: "100%",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      background:
                        "linear-gradient(rgba(0,0,0,0.2), rgba(0,0,0,0.2))",
                      borderRadius: "8px",
                      transition: "background 0.2s ease",
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.background =
                        "linear-gradient(rgba(0,0,0,0.4), rgba(0,0,0,0.4))";
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.background =
                        "linear-gradient(rgba(0,0,0,0.2), rgba(0,0,0,0.2))";
                    }}
                  >
                    <Box
                      style={{
                        width: "80px",
                        height: "80px",
                        borderRadius: "50%",
                        backgroundColor: "rgba(0,0,0,0.8)",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        border: "3px solid white",
                        boxShadow: "0 4px 12px rgba(0,0,0,0.3)",
                      }}
                    >
                      <Icon
                        source={PlayMajor}
                        tone="base"
                        style={{
                          fontSize: "32px",
                          color: "white",
                          marginLeft: "4px", // Slight offset to center the play icon
                        }}
                      />
                    </Box>
                  </Box>

                  {/* Video Title Overlay */}
                  <Text
                    variant="bodyMd"
                    style={{
                      position: "absolute",
                      bottom: "16px",
                      left: "16px",
                      right: "16px",
                      color: "white",
                      textShadow: "0 1px 3px rgba(0,0,0,0.8)",
                      fontWeight: "500",
                      backgroundColor: "rgba(0,0,0,0.6)",
                      padding: "8px 12px",
                      borderRadius: "4px",
                      backdropFilter: "blur(4px)",
                    }}
                  >
                    {secondVideoTitle}
                  </Text>
                </Box>
              ) : (
                <Box
                  padding="400"
                  background="bg-surface-subdued"
                  borderRadius="200"
                  style={{
                    textAlign: "center",
                    border: "1px solid #E1E3E5",
                  }}
                >
                  <Text variant="bodySm" tone="subdued">
                    {I18n.t("documentation.video_url_missing")}
                  </Text>
                </Box>
              )}
            </BlockStack>
          </Card>
        );
      }

      // Feature Documentation Card
      if (showFeatureDocs) {
        cards.push(
          <Card key="feature-docs">
            <BlockStack gap="300">
              <InlineGrid columns="auto 1fr" gap="200" alignItems="center">
                <Icon source={featureDocsIcon} tone="base" />
                <Text variant="headingMd" as="h3">
                  {featureDocsTitle}
                </Text>
              </InlineGrid>
              <Text variant="bodySm" tone="subdued">
                {featureDocsSubtitle}
              </Text>
              <Box paddingBlockStart="200">
                <Button
                  onClick={handleFeatureDocsClick}
                  fullWidth
                  variant="secondary"
                  disabled={!featureDocsUrl}
                >
                  {featureDocsButtonText}
                </Button>
              </Box>
            </BlockStack>
          </Card>
        );
      }

      // Chat Support Card
      if (showChatSupport) {
        cards.push(
          <Card key="chat">
            <BlockStack gap="300">
              <Text variant="headingMd" as="h3">
                {chatTitle}
              </Text>
              <Text variant="bodySm" tone="subdued">
                {chatSubtitle}
              </Text>
              <BlockStack gap="200">
                <InlineGrid columns="auto 1fr" gap="100" alignItems="center">
                  <Text variant="bodySm" fontWeight="medium">
                    {liveSupportText}
                  </Text>
                </InlineGrid>
                <Text variant="bodySm" tone="subdued">
                  {responseTimeText}
                </Text>
              </BlockStack>
              <Box paddingBlockStart="200">
                <Button onClick={handleChatClick} fullWidth variant="primary">
                  {chatButtonText}
                </Button>
              </Box>
            </BlockStack>
          </Card>
        );
      }

      return (
        <>
          <BlockStack gap="400">{cards}</BlockStack>
        </>
      );
    }

    return (
      <>
        <Card style={customStyles}>
          <BlockStack gap="300">
            {showIcon && (
              <InlineGrid columns="auto 1fr" gap="200" alignItems="center">
                <Icon source={icon} tone={iconTone} />
                <Text variant="headingMd" as="h3">
                  {title}
                </Text>
              </InlineGrid>
            )}

            {!showIcon && (
              <Text variant="headingMd" as="h3">
                {title}
              </Text>
            )}

            <Text variant="bodySm" tone="subdued">
              {description}
            </Text>

            <Button
              variant={buttonVariant}
              fullWidth={fullWidth}
              onClick={handleDocumentationClick}
            >
              {buttonText}
            </Button>
          </BlockStack>
        </Card>
      </>
    );
  };

  // Single consolidated modal for all video content
  return (
    <>
      {renderContent()}

      <Modal
        open={isVideoModalOpen}
        onClose={handleCloseVideoModal}
        title={activeVideoTitle}
        large
        backdrop={true}
      >
        <Modal.Section>
          {activeVideoUrl && (
            <Box
              style={{
                position: "relative",
                paddingBottom: "56.25%", // 16:9 aspect ratio
                height: 0,
                overflow: "hidden",
                borderRadius: "8px",
                border: "1px solid #E1E3E5",
              }}
            >
              <iframe
                src={getEmbedUrl(activeVideoUrl)}
                title={activeVideoTitle}
                frameBorder="0"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowFullScreen
                style={{
                  position: "absolute",
                  top: 0,
                  left: 0,
                  width: "100%",
                  height: "100%",
                  borderRadius: "8px",
                }}
              />
            </Box>
          )}
        </Modal.Section>
      </Modal>
    </>
  );
};

export default DocumentationCard;
