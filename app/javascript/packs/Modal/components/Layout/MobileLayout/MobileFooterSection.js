import React from "react";
import styled from "styled-components";
import { getSessionValue, isIPhone } from "../../../utilities/otpUtils";
import { STICKYFOOTER_EXCEPTION_STORES } from "../../../utilities/selectors";

const FooterWrapper = styled.div`
  position: fixed !important;
  bottom: 0 !important;
  left: 0 !important;
  right: 0 !important;
  z-index: 1000 !important;
  padding: 12px 16px !important; /* Reduced top padding to move button higher */
  padding-bottom: calc(
    12px + env(safe-area-inset-bottom)
  ) !important; /* iOS safe area - reduced padding */
  display: flex !important;
  flex-direction: column !important;
  gap: 8px !important; /* Reduced gap */
  justify-content: center !important;
  align-items: center !important;
  background-color: #fff !important;
  border-top: 1px solid #e5e7eb !important;
  box-shadow: 0 -1px 4px rgba(0, 0, 0, 0.04) !important;
  width: 100% !important;
  box-sizing: border-box !important;

  /* Ensure footer is always visible */
  min-height: 60px !important;

  /* iOS specific fixes */
  -webkit-transform: translate3d(
    0,
    0,
    0
  ) !important; /* Hardware acceleration */
  transform: translate3d(0, 0, 0) !important;
  -webkit-backface-visibility: hidden !important;
  backface-visibility: hidden !important;

  @media (min-width: 768px) {
    position: relative !important;
    border-top: none !important;
    box-shadow: none !important;
    padding-bottom: 16px !important;
  }

  /* Handle landscape mode on mobile */
  @media (max-height: 500px) and (orientation: landscape) {
    position: relative !important;
    border-top: 1px solid #e5e7eb !important;
  }

  /* Specific iOS fixes */
  @supports (-webkit-touch-callout: none) {
    /* iOS Safari specific */
    padding-bottom: calc(12px + 20px) !important; /* Reduced padding for iOS */
  }
`;

const BrandingWrapper = styled.div`
  text-align: center !important;
  font-weight: 600 !important;
  font-size: 10px !important;
  padding: 0 !important;
  margin-top: 5px !important;
  width: 100% !important;
`;

const BrandingLink = styled.span`
  margin-left: 5px !important;
  cursor: pointer !important;
  color: black !important;
  text-decoration: none !important;
  font-weight: 600 !important;
  font-size: 10px !important;
  -webkit-tap-highlight-color: transparent !important;
  user-select: none !important;

  &:hover {
    text-decoration: underline !important;
  }

  &:active {
    opacity: 0.7 !important;
  }
`;

export default function StickyFooter({ children }) {
  const settings = getSessionValue("settingSession");

  // Get current shop domain from Shopify global object
  const currentShop = window.Shopify?.shop;

  // Check if current shop is in exception list
  // const isExceptionStore =
  //   currentShop && STICKYFOOTER_EXCEPTION_STORES.includes(currentShop);
  const isExceptionStore = isIPhone;

  const footerContent = (
    <>
      {children}
      {settings?.preShowBranding && (
        <SubtleAttribution>
          <TinyLogo src="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/CK_logo_icon-1200px.png?v=1757062726" />
          COD King
        </SubtleAttribution>
      )}
    </>
  );

  // Return simple div for exception stores, styled FooterWrapper for others
  return isExceptionStore ? (
    <>{footerContent}</>
  ) : (
    <FooterWrapper>{footerContent}</FooterWrapper>
  );
}

const SubtleAttribution = styled.div`
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 4px !important;
  font-size: 9px !important;
  color: #9ca3af !important;
  margin-top: 6px !important;
  opacity: 0.8;
  width: 100% !important;
`;

const TinyLogo = styled.img`
  width: 12px !important;
  height: 12px !important;
  filter: grayscale(100%);
  opacity: 0.6;
`;
