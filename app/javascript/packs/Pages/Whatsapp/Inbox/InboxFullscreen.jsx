import React, { useEffect } from "react";
import ReactDOM from "react-dom";
import styled from "styled-components";
import { Button, Icon, InlineStack, Text } from "@shopify/polaris";
import { ChatMajor, MobileCancelMajor, SettingsMajor, WandMinor } from "@shopify/polaris-icons";
import { t } from "./format";

// Below Polaris modals (518/519) so the template picker, customer panel and
// confirm dialogs still open on top. data-polaris-layer makes Polaris place
// popovers (saved replies, emoji, labels) at this z-index + 1 instead of its
// page default, which would sit underneath the full-screen shell.
const Z_INDEX = 510;

const Shell = styled.div`
  position: fixed;
  inset: 0;
  z-index: ${Z_INDEX};
  display: flex;
  flex-direction: column;
  background: var(--p-color-bg, #f1f1f1);
`;

const Header = styled.header`
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-height: 56px;
  padding: 10px 16px;
  background: var(--p-color-bg-surface, #ffffff);
  border-bottom: 1px solid var(--p-color-border, #e3e3e3);
`;

const HeaderIcon = styled.span`
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 8px;
  background: var(--p-color-bg-surface-secondary, #f1f1f1);
`;

const Body = styled.main`
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 16px;

  @media (max-width: 760px) {
    padding: 8px;
  }
`;

const InboxFullscreen = ({ title, onClose, onSettings, onAi, children }) => {
  useEffect(() => {
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previous;
    };
  }, []);

  return ReactDOM.createPortal(
    <Shell role="dialog" aria-modal="true" aria-label={title} data-polaris-layer>
      <Header>
        <InlineStack gap="300" blockAlign="center" wrap={false}>
          <HeaderIcon>
            <Icon source={ChatMajor} tone="subdued" />
          </HeaderIcon>
          <Text as="h1" variant="headingMd">
            {title}
          </Text>
        </InlineStack>
        <InlineStack gap="200" blockAlign="center" wrap={false}>
          {onAi && (
            <Button icon={WandMinor} onClick={onAi}>
              {t("ai.header_link", "AI agent")}
            </Button>
          )}
          {onSettings && (
            <Button icon={SettingsMajor} onClick={onSettings}>
              {t("settings_link", "Inbox settings")}
            </Button>
          )}
          <Button
            icon={MobileCancelMajor}
            variant="tertiary"
            onClick={onClose}
            accessibilityLabel={t("close", "Close inbox")}
          />
        </InlineStack>
      </Header>
      <Body>{children}</Body>
    </Shell>,
    document.body,
  );
};

export default InboxFullscreen;
