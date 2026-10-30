import React, { useEffect, useState } from "react";
import ReactDOM from "react-dom";
import styled, { keyframes } from "styled-components";
import { Badge, Button, Icon, InlineStack, Text } from "@shopify/polaris";
import { MobileCancelMajor } from "@shopify/polaris-icons";
import I18n from "../../i18n-lang";

/* Rises from the bottom edge and drops back down, like the storefront sheet. */
const SHEET_MS = 280;
const SHEET_EASE = "cubic-bezier(0.32, 0.72, 0, 1)";

const fadeIn = keyframes`from { opacity: 0; } to { opacity: 1; }`;
const fadeOut = keyframes`from { opacity: 1; } to { opacity: 0; }`;
const slideUp = keyframes`from { transform: translateY(100%); } to { transform: translateY(0); }`;
const slideDown = keyframes`from { transform: translateY(0); } to { transform: translateY(100%); }`;

const Backdrop = styled.div`
  position: fixed;
  inset: 0;
  z-index: 520;
  display: flex;
  align-items: flex-end;
  padding: 16px 16px 0;
  background: rgba(0, 0, 0, 0.55);
  animation: ${(props) => (props.$closing ? fadeOut : fadeIn)} ${SHEET_MS}ms
    ${SHEET_EASE} both;

  @media (max-width: 760px) {
    padding: 0;
  }

  @media (prefers-reduced-motion: reduce) {
    animation: none;
  }
`;

const Panel = styled.div`
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  margin: 0 auto;
  overflow: hidden;
  /* Flush with the bottom of the window, so only the top corners are round. */
  border-radius: 12px 12px 0 0;
  background: var(--p-color-bg, #f1f1f1);
  box-shadow: 0 -8px 40px rgba(0, 0, 0, 0.28);
  animation: ${(props) => (props.$closing ? slideDown : slideUp)} ${SHEET_MS}ms
    ${SHEET_EASE} both;

  @media (max-width: 760px) {
    border-radius: 0;
  }

  @media (prefers-reduced-motion: reduce) {
    animation: none;
  }
`;

const Header = styled.header`
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 16px;
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

const Body = styled.div`
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-columns: ${(props) =>
    props.$withPreview ? "236px minmax(0, 1fr) 380px" : "236px minmax(0, 1fr)"};
  grid-template-areas: ${(props) =>
    props.$withPreview ? '"rail content preview"' : '"rail content"'};

  @media (max-width: 1180px) {
    grid-template-columns: ${(props) =>
      props.$withPreview ? "minmax(0, 1fr) 340px" : "minmax(0, 1fr)"};
    grid-template-rows: auto minmax(0, 1fr);
    grid-template-areas: ${(props) =>
      props.$withPreview
        ? '"rail rail" "content preview"'
        : '"rail" "content"'};
  }

  @media (max-width: 760px) {
    grid-template-columns: minmax(0, 1fr);
    grid-template-rows: auto auto minmax(0, 1fr);
    grid-template-areas:
      "rail"
      "preview"
      "content";
  }
`;

const Rail = styled.nav`
  --sn-text: #303030;
  --sn-text-subdued: #616161;
  --sn-icon: #4a4a4a;
  --sn-bg-hover: #f1f1f1;
  --sn-bg-active: #ebebeb;
  --sn-bg-pressed: #e3e3e3;

  grid-area: rail;
  min-height: 0;
  overflow-y: auto;
  padding: 12px;
  background: var(--p-color-bg-surface, #ffffff);
  border-right: 1px solid var(--p-color-border, #e3e3e3);

  @media (max-width: 1180px) {
    display: flex;
    gap: 6px;
    align-items: center;
    overflow-x: auto;
    overflow-y: hidden;
    padding: 8px 12px;
    border-right: none;
    border-bottom: 1px solid var(--p-color-border, #e3e3e3);
  }
`;

const RailGroup = styled.div`
  & + & {
    margin-top: 14px;
  }

  @media (max-width: 1180px) {
    display: contents;
  }
`;

const RailGroupTitle = styled.h3`
  margin: 0 0 2px;
  padding: 4px;
  font-size: 0.8125rem;
  line-height: 1.25rem;
  font-weight: 600;
  letter-spacing: 0;
  text-transform: uppercase;
  color: var(--sn-text);

  @media (max-width: 1180px) {
    display: none;
  }
`;

const RailItem = styled.button`
  display: flex;
  align-items: center;
  gap: 4px;
  width: 100%;
  margin: 0;
  padding: 8px;
  border: 0;
  border-radius: 8px;
  background: ${(props) =>
    props.$active ? "var(--sn-bg-active)" : "transparent"};
  color: var(--sn-text);
  font: inherit;
  font-size: 13px;
  line-height: 20px;
  font-weight: ${(props) => (props.$active ? 600 : 400)};
  text-align: start;
  cursor: pointer;
  transition: background-color 0.1s ease;

  &:hover {
    background: ${(props) =>
      props.$active ? "var(--sn-bg-active)" : "var(--sn-bg-hover)"};
  }

  &:active {
    background: var(--sn-bg-pressed);
  }

  @media (max-width: 1180px) {
    width: auto;
    flex: 0 0 auto;
    white-space: nowrap;
  }
`;

const RailItemIcon = styled.span`
  display: block;
  flex: none;
  width: 20px;
  height: 20px;

  svg {
    width: 20px;
    height: 20px;
    display: block;
    fill: var(--sn-icon);
  }
`;

const RailItemLabel = styled.span`
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
`;

const Content = styled.div`
  grid-area: content;
  min-height: 0;
  overflow-y: auto;
  padding: 24px;

  @media (max-width: 760px) {
    padding: 16px;
  }
`;

/* Its own scroll container, so the fields scroll under a preview that stays
   put instead of the whole modal scrolling as one. */
const Preview = styled.aside`
  grid-area: preview;
  min-height: 0;
  overflow-y: auto;
  padding: 16px;
  background: var(--p-color-bg-surface-secondary, #f7f7f7);
  border-left: 1px solid var(--p-color-border, #e3e3e3);

  @media (max-width: 1180px) {
    padding-left: 0;
  }

  @media (max-width: 760px) {
    max-height: 46vh;
    padding: 12px;
    border-left: none;
    border-bottom: 1px solid var(--p-color-border, #e3e3e3);
  }
`;

const Footer = styled.footer`
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 16px;
  background: var(--p-color-bg-surface, #ffffff);
  border-top: 1px solid var(--p-color-border, #e3e3e3);
`;

/**
 * Full-screen editor shell: section rail on the left, the fields in the middle
 * and a preview pinned on the right. Purely presentational — the caller owns
 * the sections, the field markup and the save.
 */
const UiCustomizationModal = ({
  open,
  title,
  titleIcon,
  titleBadge,
  sections = [],
  activeSection,
  onSelectSection,
  onClose,
  onSave,
  onDiscard,
  isSaving,
  isDirty,
  footerHelp,
  preview,
  children,
}) => {
  const [mounted, setMounted] = useState(open);
  const [closing, setClosing] = useState(false);

  useEffect(() => {
    if (open) {
      setMounted(true);
      setClosing(false);
      return undefined;
    }
    if (!mounted) return undefined;
    setClosing(true);
    const timer = setTimeout(() => {
      setMounted(false);
      setClosing(false);
    }, SHEET_MS);
    return () => clearTimeout(timer);
  }, [open, mounted]);

  useEffect(() => {
    if (!mounted) return undefined;
    const onKeyDown = (event) => {
      if (event.key === "Escape") onClose();
    };
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [mounted, onClose]);

  if (!mounted) return null;

  const groups = sections.reduce((acc, section) => {
    const group = acc.find((item) => item.title === section.group);
    if (group) group.items.push(section);
    else acc.push({ title: section.group, items: [section] });
    return acc;
  }, []);

  return ReactDOM.createPortal(
    <Backdrop
      $closing={closing}
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <Panel
        $closing={closing}
        role="dialog"
        aria-modal="true"
        aria-label={typeof title === "string" ? title : undefined}
      >
        <Header>
          <InlineStack gap="200" blockAlign="center">
            {titleIcon && (
              <HeaderIcon>
                <Icon source={titleIcon} tone="base" />
              </HeaderIcon>
            )}
            <Text variant="headingMd" as="h2">
              {title}
            </Text>
            {titleBadge}
          </InlineStack>
          <Button
            variant="tertiary"
            icon={MobileCancelMajor}
            onClick={onClose}
            accessibilityLabel={I18n.t("ui_customization_modal.close")}
          />
        </Header>

        <Body $withPreview={!!preview}>
          <Rail>
            {groups.map((group) => (
              <RailGroup key={group.title || "default"}>
                {group.title && (
                  <RailGroupTitle>{group.title}</RailGroupTitle>
                )}
                {group.items.map((section) => (
                  <RailItem
                    key={section.id}
                    type="button"
                    $active={section.id === activeSection}
                    onClick={() => onSelectSection(section.id)}
                  >
                    {section.icon && (
                      <RailItemIcon>
                        <section.icon />
                      </RailItemIcon>
                    )}
                    <RailItemLabel>{section.label}</RailItemLabel>
                    {section.badge && <Badge tone="info">{section.badge}</Badge>}
                  </RailItem>
                ))}
              </RailGroup>
            ))}
          </Rail>

          <Content>{children}</Content>

          {preview && <Preview>{preview}</Preview>}
        </Body>
      </Panel>
    </Backdrop>,
    document.body
  );
};

export default UiCustomizationModal;
