import React, { useState } from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import shallow from "zustand/shallow";
import SlidingOrderSummary from "../DesktopLayout/DesktopSlider";
import { formatCurrency, isIPhone } from "../../../utilities/otpUtils";
import { STICKYFOOTER_EXCEPTION_STORES } from "../../../utilities/selectors";

const FooterWrapper = styled.div`
  position: relative !important; /* Changed from fixed to relative to flow after content */
  width: 100% !important;
  padding: 10px 16px !important;
  padding-top: 0px !important; /* No top padding to remove gap */
  padding-bottom: 16px !important;
  display: flex !important;
  flex-direction: column !important;
  gap: 6px !important;
  justify-content: center !important;
  align-items: center !important;
  background-color: #fff !important;
  border-top: 1px solid #e5e7eb !important;
  margin-top: 0px !important; /* No margin to remove gap */

  @media (min-width: 768px) {
    border-top: none !important;
    box-shadow: none !important;
  }
`;

const FooterContent = styled.div`
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  width: 100%;
  max-width: 720px;
`;

const SummaryWrapper = styled.div`
  display: flex;
  flex-direction: column;
`;

const OrderPrice = styled.div`
  font-size: 18px;
  font-weight: 700;
  line-height: 1.2;
  color: #111827;
`;

const OrderDetailsLink = styled.button`
  font-size: 12px;
  color: rgba(55, 65, 81, 0.7);
  display: flex;
  align-items: center;
  background: none;
  border: none;
  cursor: pointer;
  padding: 0;
  margin-top: 4px;

  svg {
    margin-left: 4px;
    transform: rotate(180deg);
  }
`;

const ButtonWrapper = styled.div`
  flex: 1;
  min-width: 120px;

  button {
    width: 100%;
  }
`;

const BrandingWrapper = styled.div`
  font-size: 10px;
  color: #9ca3af;
`;

const BrandingLink = styled.span`
  cursor: pointer;
  font-weight: bold;
  color: #111827;
`;

const StickyFooterWithSummary = ({ children }) => {
  const [isSliderOpen, setSliderOpen] = useState(false);

  const { currentCartData, orderSummary } = useOtpStore(
    (state) => ({
      currentCartData: state.currentCartData,
      orderSummary: state.orderSummary,
    }),
    shallow
  );

  const totalPrice = (currentCartData?.total_price || 0) / 100;
  const currencyCode = currentCartData?.currency || "INR";

  // Get current shop domain from Shopify global object
  const currentShop = window.Shopify?.shop;

  // Check if current shop is in exception list
  // const isExceptionStore =
  //   currentShop && STICKYFOOTER_EXCEPTION_STORES.includes(currentShop);
  const isExceptionStore = isIPhone;

  const toggleSummary = () => setSliderOpen(true);

  const decodeHTMLEntities = (text) => {
    const parser = new DOMParser();
    return parser.parseFromString(text, "text/html").documentElement
      .textContent;
  };

  const footerContent = (
    <>
      <FooterContent>
        <SummaryWrapper>
          <OrderPrice>{formatCurrency(totalPrice, currencyCode)}</OrderPrice>
          <OrderDetailsLink onClick={toggleSummary}>
            View Details
            <svg width="16" height="16" fill="currentColor" viewBox="0 0 16 16">
              <path d="m8 8.781 3.3-3.3.943.943L8 10.667 3.758 6.424l.943-.943z" />
            </svg>
          </OrderDetailsLink>
        </SummaryWrapper>
        <ButtonWrapper>{children}</ButtonWrapper>
      </FooterContent>

      <SubtleAttribution>
        <TinyLogo src="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/CK_logo_icon-1200px.png?v=1757062726" />
        COD King
      </SubtleAttribution>
    </>
  );

  return (
    <>
      {/* Conditionally render FooterWrapper or plain div - iPhone exception */}
      {isExceptionStore ? (
        <>{children}</>
      ) : (
        <FooterWrapper>{footerContent}</FooterWrapper>
      )}

      <SlidingOrderSummary
        isSliderOpen={isSliderOpen}
        orderSummary={orderSummary}
        setSliderOpen={setSliderOpen}
        decodeHTMLEntities={decodeHTMLEntities}
      />
    </>
  );
};

export default StickyFooterWithSummary;

const SubtleAttribution = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 4px !important;
  font-size: 9px !important;
  color: #9ca3af !important;
  margin-top: 4px !important;
  opacity: 0.8;
`;

const TinyLogo = styled.img`
  width: 12px !important;
  height: 12px !important;
  filter: grayscale(100%);
  opacity: 0.6;
`;
