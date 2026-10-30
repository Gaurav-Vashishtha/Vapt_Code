import React from "react";
import styled, { css, keyframes } from "styled-components";
import { BlockStack, Text } from "@shopify/polaris";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { formatMoney } from "../money";
import { t } from "../i18n";

/* A static preview of the storefront button stack (BTN-7). It mirrors what
   the loader renders from the same config: label with {total}, subtitle,
   colours, border, radius, shadow, icon, animation, placement, and the
   theme's own buttons with the rename and show / hide choices applied. */

const pulse = keyframes`
  0%, 100% { transform: scale(1); }
  50% { transform: scale(1.03); }
`;
const shake = keyframes`
  0%, 64%, 100% { transform: none; }
  68% { transform: translateY(-5px) rotate(-2.5deg); }
  74% { transform: translateY(3px) rotate(2.5deg); }
  80% { transform: translateY(-4px) rotate(-2deg); }
  86% { transform: translateY(2px) rotate(2deg); }
  92% { transform: translateY(-2px) rotate(-1deg); }
`;

const SHADOWS = {
  none: "none",
  sm: "0 1px 2px rgba(0,0,0,.18)",
  md: "0 4px 10px rgba(0,0,0,.18)",
  lg: "0 10px 24px rgba(0,0,0,.22)",
};

const ICONS = {
  cash: "M3 6h18v12H3V6Zm2 2v8h14V8H5Zm7 1.5a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5ZM6.5 9.5h1v1h-1v-1Zm10 4h1v1h-1v-1Z",
  truck: "M2 6h12v9h-1.2a2.5 2.5 0 0 0-4.6 0H7.8a2.5 2.5 0 0 0-4.6 0H2V6Zm13 3h3.6L22 12.4V15h-1.2a2.5 2.5 0 0 0-4.6 0H15V9ZM5.5 17.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Zm13 0a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z",
  cart: "M3 4h2.6l.6 3H21l-1.6 8H7.4L5 5H3V4Zm5.2 10h10.2l1.1-5H7.2l1 5ZM9 20a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Zm8 0a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z",
  bolt: "M13 2 4 14h6l-1 8 9-12h-6l1-8Z",
};

const Stage = styled.div`
  border: 1px solid var(--p-color-border-secondary, #e3e3e3);
  border-radius: 12px;
  background: #ffffff;
  padding: 16px;
  color: #1a1a1a;
  font-size: 14px;
`;

const Product = styled.div`
  display: flex;
  gap: 12px;
  align-items: center;
  margin-bottom: 14px;

  i {
    flex: 0 0 auto;
    width: 56px;
    height: 56px;
    border-radius: 8px;
    background: linear-gradient(135deg, #e9e9ec, #f6f6f7);
  }
`;

const Stack = styled.div`
  display: flex;
  flex-direction: column;
  gap: 8px;
`;

const ThemeButton = styled.div`
  height: 46px;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  border: 1px solid #1a1a1a;
  background: ${(p) => (p.$solid ? "#1a1a1a" : "transparent")};
  color: ${(p) => (p.$solid ? "#ffffff" : "#1a1a1a")};
`;

const CodButton = styled.div`
  min-height: ${(p) => Number(p.$s.height) || 48}px;
  width: ${(p) => (p.$s.full_width === false ? "auto" : "100%")};
  align-self: ${(p) => (p.$s.full_width === false ? "flex-start" : "stretch")};
  padding: 6px 18px;
  display: inline-flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 2px;
  background: ${(p) => p.$s.bg};
  color: ${(p) => p.$s.color};
  border: ${(p) => Number(p.$s.border_width) || 0}px solid ${(p) => p.$s.border_color};
  border-radius: ${(p) => Number(p.$s.radius) || 0}px;
  box-shadow: ${(p) => SHADOWS[p.$s.shadow] || "none"};
  font-size: ${(p) => Number(p.$s.font_size) || 16}px;
  font-weight: ${(p) => (p.$s.bold === false ? 500 : 700)};
  line-height: 1.2;
  text-align: center;
  ${(p) =>
    p.$s.animation === "pulse" &&
    css`
      animation: ${pulse} 1.6s ease-in-out infinite;
    `}
  ${(p) =>
    p.$s.animation === "shake" &&
    css`
      animation: ${shake} 2.4s infinite;
    `}

  @media (prefers-reduced-motion: reduce) {
    animation: none;
  }

  span[data-main] {
    display: inline-flex;
    align-items: center;
    gap: 8px;
  }

  svg {
    width: 1.15em;
    height: 1.15em;
    fill: currentColor;
    flex: 0 0 auto;
  }

  small {
    font-size: 0.75em;
    font-weight: 400;
    opacity: 0.85;
  }
`;

const Phone = styled.div`
  position: relative;
  border: 1px solid var(--p-color-border-secondary, #e3e3e3);
  border-radius: 12px;
  background: #f6f6f7;
  height: 120px;
  overflow: hidden;

  > div {
    position: absolute;
    inset-inline: 0;
    bottom: 0;
    padding: 8px 10px;
    background: #ffffff;
    border-top: 1px solid #e3e3e3;
  }
`;

const FIXTURE_PRICE_CENTS = 249900;

const labelOf = (labels, fallback, total) =>
  String((labels && labels.default) || fallback || "").replace(/\{total\}/g, total);

export const CodButtonMock = ({ style, label, subtitle }) => (
  <CodButton $s={style || {}}>
    <span data-main>
      {style && ICONS[style.icon] && (
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d={ICONS[style.icon]} />
        </svg>
      )}
      <span>{label}</span>
    </span>
    {subtitle ? <small>{subtitle}</small> : null}
  </CodButton>
);

const own = (labels, fallback) => (labels && labels.default) || fallback;

const ButtonPreview = ({ config }) => {
  const bootstrap = useCodFormBootstrap();
  const button = (config && config.button) || {};
  const theme = (config && config.theme) || {};
  const hide = theme.hide || {};
  const style = button.style || {};
  const total = formatMoney(FIXTURE_PRICE_CENTS, bootstrap && bootstrap.moneyFormat, bootstrap && bootstrap.currency);
  const label = labelOf(button.labels, "Buy with COD", total);
  const subtitle = labelOf(button.subtitles, "", total);
  const position = (button.placement && button.placement.position) || "below";

  const cod = <CodButtonMock key="cod" style={style} label={label} subtitle={subtitle} />;
  const themeButtons = [
    !hide.add_to_cart && <ThemeButton key="atc">{own(theme.rename_add_to_cart, t("buttons.preview_add_to_cart", "Add to cart"))}</ThemeButton>,
    !hide.buy_now && (
      <ThemeButton key="buy" $solid>
        {own(theme.rename_buy_now, t("buttons.preview_buy_now", "Buy it now"))}
      </ThemeButton>
    ),
  ].filter(Boolean);

  // Cart page / cart drawer: the COD button sits above the theme's Checkout button, and
  // Checkout is hidden only while the COD button is there.
  const cartStage = (title, surface, hidden, rename) => {
    const codOn = !!(surface && surface.enabled);
    return (
      <BlockStack gap="200">
        <Text as="h3" variant="headingSm">
          {title}
        </Text>
        <Stage>
          <Stack>
            {codOn && (
              <CodButtonMock
                style={{ ...style, animation: "none", full_width: true }}
                label={labelOf(surface.labels, "Checkout with COD", total)}
              />
            )}
            {!(hidden && codOn) && <ThemeButton $solid>{own(rename, t("buttons.preview_checkout", "Check out"))}</ThemeButton>}
          </Stack>
        </Stage>
      </BlockStack>
    );
  };

  return (
    <BlockStack gap="400">
      <BlockStack gap="200">
        <Text as="h3" variant="headingSm">
          {t("buttons.preview_product", "Product page")}
        </Text>
        <Stage>
          <Product>
            <i />
            <div>
              <div style={{ fontWeight: 600 }}>{t("buttons.preview_product_title", "Sample product")}</div>
              <div>{total}</div>
            </div>
          </Product>
          <Stack>{position === "above" ? [cod, ...themeButtons] : [...themeButtons, cod]}</Stack>
        </Stage>
        {position === "custom" && (
          <Text as="p" variant="bodySm" tone="subdued">
            {t("buttons.preview_custom_note", "With a custom selector the button is placed inside that element on your theme.")}
          </Text>
        )}
      </BlockStack>

      {button.sticky && button.sticky.enabled && (
        <BlockStack gap="200">
          <Text as="h3" variant="headingSm">
            {t("buttons.preview_sticky", "Sticky button on mobile")}
          </Text>
          <Phone>
            <div>
              <CodButtonMock style={{ ...style, animation: "none", full_width: true }} label={labelOf(button.sticky.labels, label, total)} />
            </div>
          </Phone>
        </BlockStack>
      )}

      {cartStage(t("buttons.cart_page", "Cart page"), button.cart, hide.checkout, theme.rename_checkout)}
      {cartStage(t("buttons.cart_drawer", "Cart drawer"), button.drawer, hide.drawer_checkout, theme.rename_drawer_checkout)}
    </BlockStack>
  );
};

export default ButtonPreview;
