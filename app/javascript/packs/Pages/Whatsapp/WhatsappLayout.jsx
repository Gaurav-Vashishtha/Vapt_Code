import React from "react";
import { Page } from "@shopify/polaris";
import { navigateTo } from "../../../utils/navigate";

// Shared shell for every page under /features/whatsapp/*.
// Renders the Polaris Page title plus the way back to Business Brand WhatsApp. Only
// the hub itself passes hideBack: everything else is reached from it, and a
// merchant should never have to use the sidebar to get back one level.
const WhatsappLayout = ({
  title,
  titleMetadata,
  subtitle,
  backTo = "/features/whatsapp",
  backLabel = "Business Brand WhatsApp",
  onBack,
  // Pages the sidebar links to directly have nothing to go back to.
  hideBack = false,
  primaryAction,
  secondaryActions,
  children,
}) => {
  return (
    <Page
      title={title}
      titleMetadata={titleMetadata}
      subtitle={subtitle}
      fullWidth={true}
      backAction={
        hideBack
          ? undefined
          : {
              content: backLabel,
              onAction: () => (onBack ? onBack() : navigateTo(backTo)),
            }
      }
      primaryAction={primaryAction}
      secondaryActions={secondaryActions}
    >
      {children}
    </Page>
  );
};

export default WhatsappLayout;
