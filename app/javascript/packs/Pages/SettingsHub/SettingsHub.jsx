import React, {
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { BlockStack, Page, Text } from "@shopify/polaris";
import styled from "styled-components";
import { StoreContext } from "../../Context/Store";
import WebhookEndpoints from "../Webhooks/WebhookEndpoints";
import { navigateTo } from "../../../utils/navigate";
import LanguageDropdown from "../../Components/Integrations/LanguageDropdown";
import FeatureCallout from "../../Components/FeatureCallout";
import { SectionCard } from "../../Components/SettingsPrimitives";
import {
  SETTINGS_GROUPS,
  findItemByPath,
  getFirstVisibleItem,
  t,
  visibleItems,
} from "./registry";
import { toHubPath } from "./hubUrl";
import useCodFormBootstrap, { lastKnownModuleFlag } from "../CodForm/useCodFormBootstrap";

// Longest the landing page waits for GET /cod_form/bootstrap before it selects an item.
const COD_FORM_LANDING_WAIT_MS = 1500;

const HubShell = styled.div`
  --sn-width: 264px;
  --sn-text: #303030;
  --sn-text-subdued: #616161;
  --sn-icon: #4a4a4a;
  --sn-bg: #ffffff;
  --sn-bg-hover: #f1f1f1;
  --sn-bg-active: #ebebeb;
  --sn-bg-pressed: #e3e3e3;
  --sn-border: #e3e3e3;
  --sn-focus: #005bd3;
  --sn-radius: 8px;

  display: flex;
  gap: 16px;
  align-items: flex-start;

  /* Below 768px only the top bar + content stay in flow (the drawer and its
     backdrop are position:fixed and don't participate in this layout). */
  @media (max-width: 768px) {
    flex-direction: column;
    gap: 0;
  }
`;

const Sidebar = styled.div`
  box-sizing: border-box;
  width: var(--sn-width);
  flex: 0 0 var(--sn-width);
  display: flex;
  flex-direction: column;
  background: var(--sn-bg);
  border: 1px solid var(--sn-border);
  border-radius: var(--sn-radius);
  -webkit-font-smoothing: antialiased;

  *,
  *::before,
  *::after {
    box-sizing: border-box;
  }

  /* Below 768px navigation moves into the slide-out drawer instead of
     stacking the full nav above the content. */
  @media (max-width: 768px) {
    display: none;
  }
`;

const MobileTopBar = styled.div`
  display: none;

  @media (max-width: 768px) {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    width: 100%;
    padding: 12px 8px;
    margin: 0 -8px 12px;
    position: sticky;
    top: 0;
    z-index: 10;
    background: var(--p-color-bg-fill-secondary, #f1f1f1);
    border-bottom: 1px solid var(--sn-border);
  }
`;

const MobileTopBarText = styled.div`
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
`;

const HamburgerButton = styled.button`
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  flex: none;
  padding: 0;
  border: 1px solid var(--sn-border);
  border-radius: var(--sn-radius);
  background: var(--sn-bg);
  cursor: pointer;

  svg {
    width: 18px;
    height: 18px;
    fill: var(--sn-icon);
  }

  &:hover {
    background: var(--sn-bg-hover);
  }
  &:active {
    background: var(--sn-bg-pressed);
  }
  &:focus-visible {
    outline: 2px solid var(--sn-focus);
    outline-offset: 1px;
  }
`;

const MobileTopBarTitle = styled.span`
  font-size: 1.25rem;
  line-height: 1.5rem;
  font-weight: 700;
  color: var(--sn-text);
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
`;

const MobileTopBarSubtitle = styled.span`
  font-size: 13px;
  line-height: 18px;
  font-weight: 400;
  color: var(--sn-text-subdued);
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
`;

const DrawerBackdrop = styled.div`
  display: none;

  @media (max-width: 768px) {
    display: block;
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    z-index: 20;
    opacity: ${(props) => (props.$open ? 1 : 0)};
    pointer-events: ${(props) => (props.$open ? "auto" : "none")};
    transition: opacity 0.2s ease;
  }
`;

const Drawer = styled.div`
  display: none;

  @media (max-width: 768px) {
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    position: fixed;
    top: 0;
    bottom: 0;
    right: 0;
    width: min(84vw, 320px);
    background: var(--sn-bg);
    z-index: 21;
    box-shadow: -2px 0 12px rgba(0, 0, 0, 0.15);
    transform: translateX(${(props) => (props.$open ? "0" : "100%")});
    transition: transform 0.22s ease;
    overflow-y: auto;

    *,
    *::before,
    *::after {
      box-sizing: border-box;
    }
  }
`;

const DrawerHeader = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px;
  border-bottom: 1px solid var(--sn-border);
`;

const DrawerTitle = styled.span`
  font-size: 15px;
  font-weight: 600;
  color: var(--sn-text);
`;

const DrawerCloseButton = styled(HamburgerButton)``;

const SearchArea = styled.div`
  padding: 12px 12px 0;
`;

const SearchField = styled.div`
  position: relative;
  display: block;

  svg {
    position: absolute;
    inset-inline-start: 8px;
    top: 50%;
    transform: translateY(-50%);
    width: 16px;
    height: 16px;
    fill: var(--sn-icon);
    pointer-events: none;
  }
`;

const SearchInput = styled.input`
  width: 100%;
  height: 32px;
  padding: 0 8px 0 30px;
  font: inherit;
  font-size: 13px;
  line-height: 20px;
  color: var(--sn-text);
  background: #fdfdfd;
  border: 1px solid #8a8a8a;
  border-radius: 8px;
  box-shadow: inset 0 1px 0 rgba(0, 0, 0, 0.04);
  appearance: none;

  &::placeholder {
    color: #8a8a8a;
  }

  &:focus {
    outline: 2px solid var(--sn-focus);
    outline-offset: -1px;
    border-color: transparent;
  }

  &::-webkit-search-cancel-button {
    cursor: pointer;
  }
`;

const Section = styled.div`
  padding: 8px;

  & + & {
    border-top: 1px solid var(--sn-border);
  }
`;

const SectionTitle = styled.h2`
  margin: 0;
  margin-block-end: 0;
  padding: 4px;
  font-size: 0.8125rem;
  line-height: 1.25rem;
  font-weight: 600;
  letter-spacing: 0;
  text-transform: uppercase;
  color: var(--sn-text);
`;

const List = styled.ul`
  list-style: none;
  margin: 0;
  padding: 0;
`;

const Item = styled.a`
  display: grid;
  grid-template-columns: 20px minmax(0, 1fr);
  gap: 4px;
  align-items: start;
  width: 100%;
  margin: 0;
  padding: 8px;
  border: 0;
  border-radius: var(--sn-radius);
  background: ${(props) =>
    props.$selected ? "var(--sn-bg-active)" : "transparent"};
  color: var(--sn-text);
  font: inherit;
  font-size: 13px;
  line-height: 20px;
  font-weight: ${(props) => (props.$selected ? 600 : 400)};
  text-align: start;
  text-decoration: none;
  cursor: pointer;
  transition: background-color 0.1s ease;

  &:hover {
    background: ${(props) =>
      props.$selected ? "var(--sn-bg-active)" : "var(--sn-bg-hover)"};
  }

  &:active {
    background: var(--sn-bg-pressed);
  }

  &:focus-visible {
    outline: 2px solid var(--sn-focus);
    outline-offset: 1px;
  }

  .sn-item__icon {
    width: 20px;
    height: 20px;
    display: block;
    fill: var(--sn-icon);
    flex: none;
  }
`;

const ItemLabel = styled.span`
  min-width: 0;
`;

const EmptyResult = styled.div`
  padding: 8px 12px 12px;
  font-size: 13px;
  line-height: 20px;
  color: var(--sn-text-subdued);
`;

const ContentPane = styled.div`
  flex: 1;
  min-width: 0;

  /* The sidebar and the shell gap already supply the left gutter, and the
     hub heading should line up with the top of the sidebar. */
  .Polaris-Page {
    padding-inline-start: 0;
    padding-left: 0;
    padding-block-start: 0;
    padding-top: 0;
  }

  /* Polaris wraps the page header in a Box padded 24px top and bottom, which
     drops the heading well below the top of the sidebar. */
  .Polaris-Page > .Polaris-Box:first-child {
    padding-block-start: 0;
    padding-block-end: var(--p-space-300);
  }

  .Polaris-Page-Header__TitleWrapper {
    margin-top: 0;
  }

  /* The sticky mobile top bar already shows the section's title + subtitle,
     so each page's own Polaris header would just repeat it right below. */
  @media (max-width: 768px) {
    .Polaris-Page-Header__TitleWrapper {
      display: none;
    }
  }

  .Polaris-Page__Content {
    margin-top: 0;
    padding-top: var(--p-space-300);
  }

  @media (max-width: 768px) {
    width: 100%;
  }
`;

/* The hub's own screens are built the same way as the feature screens the
   sidebar links to: full width, a callout at the top, then section cards. */
const LanguageSettingsPage = () => (
  <Page
    title={t("settings_hub.item_language", "Language")}
    subtitle={t(
      "settings_hub.language_subtitle",
      "Choose the language of your COD King dashboard.",
    )}
    fullWidth
  >
    <BlockStack gap="400">
      <FeatureCallout
        illustration="docs"
        title={t("settings_hub.item_language", "Language")}
        description={t(
          "settings_hub.language_subtitle",
          "Choose the language of your COD King dashboard.",
        )}
        docsUrl="https://codking.tech/documentation/"
        showChat
      />
      <SectionCard
        title={t("settings_hub.language_card_title", "Dashboard language")}
        description={t(
          "settings_hub.language_card_help",
          "This changes the admin only. Storefront wording is set on each feature screen.",
        )}
      >
        <LanguageDropdown />
      </SectionCard>
    </BlockStack>
  </Page>
);

const ComingSoonPage = ({
  titleKey,
  titleFallback,
  bodyKey,
  bodyFallback,
  illustration = "docs",
}) => (
  <Page title={t(titleKey, titleFallback)} fullWidth>
    <BlockStack gap="400">
      <FeatureCallout
        illustration={illustration}
        title={t(titleKey, titleFallback)}
        description={t(bodyKey, bodyFallback)}
        docsUrl="https://codking.tech/documentation/"
        showChat
      />
      <SectionCard title={t("settings_hub.coming_soon", "Coming soon")}>
        <Text as="p" tone="subdued">
          {t(bodyKey, bodyFallback)}
        </Text>
      </SectionCard>
    </BlockStack>
  </Page>
);

const AdvancedSettingsPage = () => (
  <ComingSoonPage
    titleKey="settings_hub.item_advanced"
    titleFallback="Advanced"
    bodyKey="settings_hub.advanced_coming_body"
    bodyFallback="Advanced options like IVR confirmation calls, WhatsApp template overrides and checkout form flags will appear here so you can change them yourself. Until then, message us from Help & Support and we'll configure them for you."
  />
);

const PartnerAppsPage = () => (
  <ComingSoonPage
    illustration="customize"
    titleKey="settings_hub.item_partner_apps"
    titleFallback="Partner apps"
    bodyKey="settings_hub.partner_apps_coming_body"
    bodyFallback="Recommended partner apps and bundles will appear here."
  />
);

const INTERNAL_PAGES = {
  "/settings-hub/language": LanguageSettingsPage,
  "/settings-hub/advanced": AdvancedSettingsPage,
  "/settings-hub/webhooks": WebhookEndpoints,
  "/settings-hub/partner-apps": PartnerAppsPage,
};

const SettingsHub = ({ currentPath, children }) => {
  const {
    shop: [shop],
    setting: [setting],
    isPrepaidEnabled,
  } = useContext(StoreContext);

  const [query, setQuery] = useState("");
  const [isMobileNavOpen, setIsMobileNavOpen] = useState(false);
  const searchRef = useRef(null);
  const codForm = useCodFormBootstrap();
  const visibilityCtx = useMemo(
    () => ({ shop, setting, isPrepaidEnabled, codForm }),
    [shop, setting, isPrepaidEnabled, codForm],
  );
  const items = useMemo(() => visibleItems(visibilityCtx), [visibilityCtx]);
  const selectedItem = findItemByPath(currentPath);

  // The COD Form group is the first group when the module is on for the shop, but that flag
  // only arrives with GET /cod_form/bootstrap (`codForm` is null until then). Selecting the
  // first item before the flag is known would land a COD Form shop on OTP verification.
  // So the landing selection waits for the flag — except for a shop last seen with the module
  // off (no wait at all), and never longer than COD_FORM_LANDING_WAIT_MS.
  const [landingWaitOver, setLandingWaitOver] = useState(false);
  const codFormFlagKnown = !!codForm || landingWaitOver || lastKnownModuleFlag() === "0";
  useEffect(() => {
    if (codForm || landingWaitOver) return undefined;
    const timer = setTimeout(() => setLandingWaitOver(true), COD_FORM_LANDING_WAIT_MS);
    return () => clearTimeout(timer);
  }, [codForm, landingWaitOver]);

  // Landing on /settings-hub selects the first item, like Judge.me preselects "Import reviews".
  useEffect(() => {
    if (currentPath !== "/settings-hub") return;
    if (!codFormFlagKnown) return;
    const first = getFirstVisibleItem(visibilityCtx);
    if (first) {
      window.history.replaceState({}, "", first.path);
      window.dispatchEvent(new PopStateEvent("popstate"));
    }
  }, [currentPath, visibilityCtx, codFormFlagKnown]);

  // Jump to the top of the page whenever the settings-hub screen changes,
  // so paging through a long section doesn't leave the next one scrolled down.
  useEffect(() => {
    window.scrollTo({ top: 0, left: 0, behavior: "auto" });
  }, [currentPath]);

  // Close the mobile drawer (and restore background scroll) whenever the
  // screen changes, e.g. via browser back/forward.
  useEffect(() => {
    setIsMobileNavOpen(false);
  }, [currentPath]);

  useEffect(() => {
    if (!isMobileNavOpen) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const onKeyDown = (event) => {
      if (event.key === "Escape") setIsMobileNavOpen(false);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", onKeyDown);
    };
  }, [isMobileNavOpen]);

  // Ctrl/Cmd + Shift + F focuses search, as promised by the placeholder.
  useEffect(() => {
    const onKeyDown = (event) => {
      if (
        (event.ctrlKey || event.metaKey) &&
        event.shiftKey &&
        event.key?.toLowerCase() === "f"
      ) {
        event.preventDefault();
        searchRef.current?.focus();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const filteredItems = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return items;
    return items.filter((item) => {
      const label = t(item.labelKey, item.label).toLowerCase();
      return [label, ...(item.keywords || [])].join(" ").includes(q);
    });
  }, [items, query]);

  const handleItemClick = (event, item) => {
    // Let modified clicks (new tab/window) behave natively.
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    setIsMobileNavOpen(false);
    if (item.path !== currentPath) navigateTo(item.path);
  };

  const renderNavGroups = () => (
    <>
      {SETTINGS_GROUPS.map((group) => {
        const groupItems = filteredItems.filter(
          (item) => item.group === group.id,
        );
        if (groupItems.length === 0) return null;
        return (
          <Section key={group.id}>
            <SectionTitle>{t(group.labelKey, group.label)}</SectionTitle>
            <List>
              {groupItems.map((item) => {
                const IconSource = item.icon;
                const isSelected = selectedItem?.id === item.id;
                return (
                  <li key={item.id}>
                    <Item
                      href={toHubPath(item.path)}
                      $selected={isSelected}
                      aria-current={isSelected ? "page" : undefined}
                      onClick={(event) => handleItemClick(event, item)}
                    >
                      <IconSource
                        className="sn-item__icon"
                        aria-hidden="true"
                        focusable="false"
                      />
                      <ItemLabel>{t(item.labelKey, item.label)}</ItemLabel>
                    </Item>
                  </li>
                );
              })}
            </List>
          </Section>
        );
      })}
      {filteredItems.length === 0 && (
        <EmptyResult>
          {t("settings_hub.search_empty", "No settings found")}
        </EmptyResult>
      )}
    </>
  );

  const renderSearch = () => (
    <SearchArea>
      <SearchField>
        <svg viewBox="0 0 16 16" aria-hidden="true" focusable="false">
          <path
            fillRule="evenodd"
            d="M10.323 11.383a5.5 5.5 0 1 1-3.323-9.883 5.5 5.5 0 0 1 4.383 8.823l2.897 2.897a.749.749 0 1 1-1.06 1.06zm.677-4.383c0 2.21-1.79 4-4 4s-4-1.79-4-4 1.79-4 4-4 4 1.79 4 4"
          />
        </svg>
        <SearchInput
          ref={searchRef}
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder={t(
            "settings_hub.search_placeholder",
            "Search (Ctrl + Shift + F)",
          )}
          aria-label={t("settings_hub.search_label", "Search settings")}
        />
      </SearchField>
    </SearchArea>
  );

  const InternalPage = INTERNAL_PAGES[currentPath];
  const content = children || (InternalPage ? <InternalPage /> : null);
  const currentLabel = selectedItem
    ? t(selectedItem.labelKey, selectedItem.label)
    : t("settings_hub.title", "Settings");
  const currentGroup = selectedItem
    ? SETTINGS_GROUPS.find((group) => group.id === selectedItem.group)
    : null;
  const currentGroupLabel = currentGroup
    ? t(currentGroup.labelKey, currentGroup.label)
    : null;

  return (
    <HubShell>
      <Sidebar role="navigation" aria-label={t("settings_hub.title", "Settings")}>
        {renderSearch()}
        <nav>{renderNavGroups()}</nav>
      </Sidebar>

      <MobileTopBar>
        <MobileTopBarText>
          <MobileTopBarTitle>{currentLabel}</MobileTopBarTitle>
          {currentGroupLabel && (
            <MobileTopBarSubtitle>{currentGroupLabel}</MobileTopBarSubtitle>
          )}
        </MobileTopBarText>
        <HamburgerButton
          type="button"
          aria-label={t("settings_hub.open_nav", "Open settings menu")}
          aria-expanded={isMobileNavOpen}
          onClick={() => setIsMobileNavOpen(true)}
        >
          <svg viewBox="0 0 20 20" aria-hidden="true" focusable="false">
            <path d="M2 5h16v1.5H2zM2 9.25h16v1.5H2zM2 13.5h16V15H2z" />
          </svg>
        </HamburgerButton>
      </MobileTopBar>

      <DrawerBackdrop
        $open={isMobileNavOpen}
        onClick={() => setIsMobileNavOpen(false)}
        aria-hidden="true"
      />
      <Drawer
        $open={isMobileNavOpen}
        role="navigation"
        aria-label={t("settings_hub.title", "Settings")}
        aria-hidden={!isMobileNavOpen}
      >
        <DrawerHeader>
          <DrawerTitle>{t("settings_hub.title", "Settings")}</DrawerTitle>
          <DrawerCloseButton
            type="button"
            aria-label={t("settings_hub.close_nav", "Close settings menu")}
            onClick={() => setIsMobileNavOpen(false)}
          >
            <svg viewBox="0 0 20 20" aria-hidden="true" focusable="false">
              <path d="M5.03 4.97a.75.75 0 0 0-1.06 1.06L8.94 11l-4.97 4.97a.75.75 0 1 0 1.06 1.06L10 12.06l4.97 4.97a.75.75 0 1 0 1.06-1.06L11.06 11l4.97-4.97a.75.75 0 0 0-1.06-1.06L10 9.94z" />
            </svg>
          </DrawerCloseButton>
        </DrawerHeader>
        {renderSearch()}
        <nav>{renderNavGroups()}</nav>
      </Drawer>

      <ContentPane>{content}</ContentPane>
    </HubShell>
  );
};

export default SettingsHub;
