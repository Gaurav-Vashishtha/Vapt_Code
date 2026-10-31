import React, { useEffect, useMemo, useState } from "react";
import styled from "styled-components";
import Skeleton from "react-loading-skeleton";
import "react-loading-skeleton/dist/skeleton.css";
import {
  debugLog,
  formatCurrency,
  getSessionValue,
  // preCreateCartsForEligibleRules,
  removeSessionValue,
  saveDiscountSummaryToSession,
} from "../../../utilities/otpUtils";
import useOtpStore from "../../../stores/otpStore";
import SlidingOrderSummary from "./DesktopSlider";
import { getIsBuyNowButton } from "../../../services/domUtils";
import shallow from "zustand/shallow";
import { shinyBackboneEffectWithColor } from "./Styles/shinyBackbone";
import { CartRevertService } from "../../../services/CartRevertService";
import { shopifyAddToCartForBuyNow } from "../../../services/cartService";
import { callPartialDummyVariantId } from "../../../services/callPartialDummyVariantId";

const DesktopOrderSummary = ({ onExpand }) => {
  const [isSliderOpen, setSliderOpen] = useState(false);
  const [isExpanded, setIsExpanded] = useState(false);
  const settings = getSessionValue("settingSession");

  // Subscribing to orderSummary, cart readiness, and product fetching function
  const {
    isCartReady,
    setIsCartReady,
    isBuyNowReady,
    orderSummary,
    currentCartData,
    isPartialCartRevertToOriginalCartCompleted,
    setIsPartialCartRevertToOriginalCartCompleted,
    initializeFetchProductDetails,
  } = useOtpStore(
    (state) => ({
      isCartReady: state.isCartReady,
      isBuyNowReady: state.isBuyNowReady,
      setIsCartReady: state.setIsCartReady,
      orderSummary: state.orderSummary,
      currentCartData: state.currentCartData,
      isPartialCartRevertToOriginalCartCompleted:
        state.isPartialCartRevertToOriginalCartCompleted,
      initializeFetchProductDetails: state.initializeFetchProductDetails,
      setIsPartialCartRevertToOriginalCartCompleted:
        state.setIsPartialCartRevertToOriginalCartCompleted,
    }),
    shallow,
  );

  const summaryLoading = orderSummary?.summaryLoading || false;

  // Use currentCartData from OTP store instead of transformed cart from CartStore
  const cartState = currentCartData || {};

  // Map items to compact product data for UI
  const productData = useMemo(() => {
    return (cartState.items || []).map((item) => ({
      name: item.title,
      imageSrc: item?.featured_image?.url || item.image || "NA",
      quantity: item.quantity,
      price:
        (typeof item.discounted_price === "number"
          ? item.discounted_price
          : item.price || 0) / 100,
    }));
  }, [cartState.items]);

  const totalQuantity =
    cartState.item_count ||
    productData.reduce((acc, p) => acc + (p.quantity || 0), 0);
  const currencyCode = cartState.currency || "INR";

  // console.log("state.orderSummary", orderSummary);

  // console.log("orderSummaryData", orderSummaryData);

  // Use transformed cart totals directly (values are in minor units)
  const originalPrice = (cartState.original_total_price || 0) / 100;
  const discountedPrice = (cartState.total_price || 0) / 100;
  const discountAmount = (cartState.total_discount || 0) / 100;
  const hasDiscount = (cartState.total_discount || 0) > 0;
  const firstCartDiscount = cartState.cart_level_discount_applications?.[0];
  const discountTitle =
    firstCartDiscount?.title || cartState.discount_codes?.[0]?.code || "";

  const partialPaymentEnabled = settings?.partialPaymentEnabled === true;
  const partialPaymentFlowVersion = settings?.partialPaymentFlowVersion;

  // Save discount summary whenever values change during popup lifecycle
  useEffect(() => {
    try {
      saveDiscountSummaryToSession(discountAmount, discountTitle);
    } catch (e) {
      console.warn("Failed saving discount summary", e);
    }
  }, [discountAmount, discountTitle]);

  useEffect(() => {
    let isMounted = true;

    const initialize = async () => {
      try {
        if (!isMounted) return;
        callPartialDummyVariantId();
        await CartRevertService();
        if (getIsBuyNowButton() && isMounted) {
          await shopifyAddToCartForBuyNow();
        }
        if (isMounted) {
          await initializeFetchProductDetails();
        }
      } catch (error) {
        console.error("Error initializing DesktopOrderSummary:", error);
      }
    };

    initialize();

    return () => {
      isMounted = false;
    };
  }, []);

  const handleToggleExpand = () => {
    setIsExpanded(!isExpanded);
    setSliderOpen(!isSliderOpen);
    if (onExpand) {
      onExpand(!isExpanded);
    }
  };

  function decodeHTMLEntities(text) {
    const parser = new DOMParser();
    const decodedString = parser.parseFromString(text, "text/html")
      .documentElement.textContent;
    return decodedString;
  }

  // Compact Price Display Component for Mobile
  const CompactPriceDisplay = ({ showDiscount = true }) => {
    const currency = currencyCode === "INR" ? "₹" : currencyCode;

    return (
      <CompactPriceContainer>
        {hasDiscount && showDiscount ? (
          <>
            <PriceRow>
              <OriginalPriceMobile>
                {currency}
                {originalPrice.toFixed(2)}
              </OriginalPriceMobile>
              <FinalPriceMobile>
                {currency}
                {discountedPrice.toFixed(2)}
              </FinalPriceMobile>
            </PriceRow>
            <DiscountBadgeMobile>
              {firstCartDiscount?.value_type === "percentage"
                ? `${firstCartDiscount?.value}% OFF`
                : `FLAT ${currency}${discountAmount.toFixed(2)} OFF`}
            </DiscountBadgeMobile>
            {discountTitle ? (
              <DiscountNameMobile title={discountTitle}>
                {discountTitle}
              </DiscountNameMobile>
            ) : null}
          </>
        ) : (
          <FinalPriceMobile>
            {currency}
            {discountedPrice.toFixed(2)}
          </FinalPriceMobile>
        )}
      </CompactPriceContainer>
    );
  };

  // Compact Savings Component
  const CompactSavings = () => {
    if (!hasDiscount) return null;

    const currency = currencyCode === "INR" ? "₹" : currencyCode;

    return (
      <CompactSavingsContainer>
        <SavingsIconSmall>✓</SavingsIconSmall>
        <SavingsTextSmall>
          SAVED {currency}
          {discountAmount.toFixed(2)}
        </SavingsTextSmall>
      </CompactSavingsContainer>
    );
  };

  const renderCompactSingleProduct = () => {
    if (!productData.length) return null;

    const product = productData[0];
    const decodedName = decodeHTMLEntities(product.name);

    return (
      <CompactProductContainer>
        <ProductImageSmall
          src={product.imageSrc}
          alt={decodedName}
          onError={(e) => {
            e.target.src = "/fallback-product-image.jpg";
          }}
        />
        <ProductInfoCompact>
          <ProductTitleCompact>{decodedName}</ProductTitleCompact>
          <ProductQuantitySmall>Qty. {product.quantity}</ProductQuantitySmall>
        </ProductInfoCompact>
        <CompactPriceDisplay />
      </CompactProductContainer>
    );
  };

  const renderCompactMultipleProducts = () => {
    return (
      <CompactMultipleContainer>
        <ProductImageStackMobile>
          {productData.slice(0, 2).map((product, index) => {
            const decodedName = decodeHTMLEntities(product.name);
            return (
              <StackedImageMobile
                key={index}
                index={index}
                src={product.imageSrc}
                alt={decodedName}
                onError={(e) => {
                  e.target.src = "/fallback-product-image.jpg";
                }}
              />
            );
          })}
          {productData.length > 2 && (
            <ExtraItemsMobile>+{productData.length - 2}</ExtraItemsMobile>
          )}
        </ProductImageStackMobile>
        <MultipleProductInfo>
          <ItemCountMobile>{totalQuantity} items</ItemCountMobile>
          <CompactPriceDisplay />
        </MultipleProductInfo>
      </CompactMultipleContainer>
    );
  };

  if (!isCartReady) {
    return (
      <MobileOrderSummaryWrapper>
        <MobileOrderSummaryCard>
          <CompactOrderSummaryButton>
            <CompactHeader>
              <Skeleton width={100} height={14} />
              <Skeleton width={16} height={16} />
            </CompactHeader>
            <Skeleton height={40} style={{ marginTop: "8px" }} />
          </CompactOrderSummaryButton>
        </MobileOrderSummaryCard>
      </MobileOrderSummaryWrapper>
    );
  }

  return (
    <>
      <MobileOrderSummaryWrapper>
        <MobileOrderSummaryCard>
          <CompactOrderSummaryButton
            onClick={handleToggleExpand}
            data-testid="order-summary-widget-mobile"
          >
            <CompactHeader>
              <HeaderTitleMobile>Order summary</HeaderTitleMobile>
              <ArrowIconMobile isExpanded={isExpanded}>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 16 16"
                  fill="currentColor"
                >
                  <path d="m8 8.781 3.3-3.3.943.943L8 10.667 3.758 6.424l.943-.943z" />
                </svg>
              </ArrowIconMobile>
            </CompactHeader>

            {totalQuantity > 1
              ? renderCompactMultipleProducts()
              : renderCompactSingleProduct()}

            <CompactSavings />
          </CompactOrderSummaryButton>
        </MobileOrderSummaryCard>
      </MobileOrderSummaryWrapper>

      {/* Sliding Order Summary */}
      <SlidingOrderSummary
        isSliderOpen={isSliderOpen}
        setSliderOpen={setSliderOpen}
        decodeHTMLEntities={decodeHTMLEntities}
      />
    </>
  );
};

export default DesktopOrderSummary;

// Mobile-Optimized Styled Components
const MobileOrderSummaryWrapper = styled.div`
  position: relative !important;
  border-radius: 8px !important;
  background: linear-gradient(135deg, #9ca3af 0%, #374151 100%) !important;
  padding: 1px !important;
  margin: 0 4px !important;

  @media (min-width: 768px) {
    margin: 0 !important;
    border-radius: 12px !important;
  }
`;

const MobileOrderSummaryCard = styled.div`
  position: relative !important;
  ${shinyBackboneEffectWithColor("#f4f4f7")}
  overflow: hidden !important;
  border-radius: 8px !important;
  background: rgba(255, 255, 255, 0.95) !important;
  backdrop-filter: blur(10px) !important;
  transition: all 0.2s ease !important;

  @media (min-width: 768px) {
    border-radius: 12px !important;
  }

  &:hover {
    background: rgba(255, 255, 255, 1) !important;
    transform: translateY(-1px) !important;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.08) !important;
  }

  &:active {
    background: rgba(248, 248, 248, 1) !important;
  }
`;

const CompactOrderSummaryButton = styled.button`
  width: 100% !important;
  padding: 12px !important;
  border: none !important;
  background: transparent !important;
  cursor: pointer !important;
  text-align: left !important;
  outline: none !important;
  transition: all 0.2s ease !important;

  @media (min-width: 768px) {
    padding: 16px !important;
  }
`;

const CompactHeader = styled.div`
  display: flex !important;
  align-items: center !important;
  justify-content: space-between !important;
  margin-bottom: 8px !important;

  @media (min-width: 768px) {
    margin-bottom: 12px !important;
  }
`;

const HeaderTitleMobile = styled.span`
  font-weight: 600 !important;
  font-size: 13px !important;
  color: rgba(17, 24, 39, 0.6) !important;
  letter-spacing: -0.01em !important;

  @media (min-width: 768px) {
    font-size: 14px !important;
  }
`;

const ArrowIconMobile = styled.div`
  width: 14px !important;
  height: 14px !important;
  color: rgba(17, 24, 39, 0.4) !important;
  transition: all 0.2s ease !important;
  transform: ${(props) =>
      props.isExpanded
        ? "rotate(0deg) !important;"
        : "rotate(-90deg) !important;"}
    @media (min-width: 768px) {
    width: 16px !important;
    height: 16px !important;
  }

  svg {
    width: 100% !important;
    height: 100% !important;
  }
`;

const CompactProductContainer = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 8px !important;

  @media (min-width: 768px) {
    gap: 12px !important;
  }
`;

const ProductImageSmall = styled.img`
  width: 32px !important;
  height: 32px !important;
  border-radius: 50% !important;
  border: 0.5px solid rgba(17, 24, 39, 0.05) !important;
  background: #ffffff !important;
  object-fit: cover !important;
  flex-shrink: 0 !important;

  @media (min-width: 768px) {
    width: 40px !important;
    height: 40px !important;
  }
`;

const ProductInfoCompact = styled.div`
  flex: 1 !important;
  min-width: 0 !important;
  display: flex !important;
  flex-direction: column !important;
  gap: 2px !important;

  @media (min-width: 768px) {
    gap: 4px !important;
  }
`;

const ProductTitleCompact = styled.p`
  font-weight: 500 !important;
  font-size: 12px !important;
  color: #111827 !important;
  line-height: 1.3 !important;
  margin: 0 !important;
  display: -webkit-box !important;
  -webkit-line-clamp: 1 !important;
  -webkit-box-orient: vertical !important;
  overflow: hidden !important;

  @media (min-width: 768px) {
    font-size: 14px !important;
    -webkit-line-clamp: 2 !important;
  }
`;

const ProductQuantitySmall = styled.p`
  font-size: 11px !important;
  color: rgba(17, 24, 39, 0.6) !important;
  margin: 0 !important;

  @media (min-width: 768px) {
    font-size: 12px !important;
  }
`;

const CompactPriceContainer = styled.div`
  flex-shrink: 0 !important;
  display: flex !important;
  flex-direction: column !important;
  align-items: flex-end !important;
  gap: 2px !important;
`;

const PriceRow = styled.div`
  display: flex !important;
  flex-direction: column !important;
  align-items: flex-end !important;
  gap: 2px !important;
`;

const OriginalPriceMobile = styled.span`
  font-size: 11px !important;
  font-weight: 500 !important;
  color: rgba(17, 24, 39, 0.5) !important;
  text-decoration: line-through !important;
  text-decoration-color: rgba(239, 68, 68, 0.8) !important;

  @media (min-width: 768px) {
    font-size: 12px !important;
  }
`;

const FinalPriceMobile = styled.span`
  font-size: 16px !important;
  font-weight: 700 !important;
  color: #111827 !important;
  letter-spacing: -0.01em !important;

  @media (min-width: 768px) {
    font-size: 18px !important;
  }
`;

const DiscountBadgeMobile = styled.div`
  background: linear-gradient(135deg, #10b981, #059669) !important;
  color: white !important;
  font-size: 8px !important;
  font-weight: 600 !important;
  padding: 1px 4px !important;
  border-radius: 3px !important;
  letter-spacing: 0.02em !important;
  text-transform: uppercase !important;

  @media (min-width: 768px) {
    font-size: 9px !important;
    padding: 2px 6px !important;
    border-radius: 4px !important;
  }
`;

const DiscountNameMobile = styled.div`
  font-size: 9px !important;
  color: rgba(17, 24, 39, 0.6) !important;
  margin-top: 2px !important;
  max-width: 160px !important;
  white-space: nowrap !important;
  overflow: hidden !important;
  text-overflow: ellipsis !important;

  @media (min-width: 768px) {
    font-size: 10px !important;
    max-width: 200px !important;
  }
`;

const CompactMultipleContainer = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 8px !important;

  @media (min-width: 768px) {
    gap: 12px !important;
  }
`;

const ProductImageStackMobile = styled.div`
  display: flex !important;
  align-items: center !important;
`;

const StackedImageMobile = styled.img`
  width: 28px !important;
  height: 28px !important;
  border-radius: 50% !important;
  border: 0.5px solid rgba(17, 24, 39, 0.05) !important;
  background: #ffffff !important;
  object-fit: cover !important;
  margin-left: ${(props) =>
    props.index > 0 ? "-6px !important;" : "0 !important;"}
  z-index: ${(props) => 10 - props.index} !important;

  @media (min-width: 768px) {
    width: 32px !important;
    height: 32px !important;
    margin-left: ${(props) =>
      props.index > 0 ? "-8px !important;" : "0 !important;"}
  }
`;

const ExtraItemsMobile = styled.div`
  width: 28px !important;
  height: 28px !important;
  border-radius: 50% !important;
  background: rgba(17, 24, 39, 0.1) !important;
  border: 0.5px solid rgba(17, 24, 39, 0.05) !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  font-size: 10px !important;
  font-weight: 600 !important;
  color: rgba(17, 24, 39, 0.7) !important;
  margin-left: -6px !important;

  @media (min-width: 768px) {
    width: 32px !important;
    height: 32px !important;
    font-size: 11px !important;
    margin-left: -8px !important;
  }
`;

const MultipleProductInfo = styled.div`
  flex: 1 !important;
  display: flex !important;
  flex-direction: column !important;
  align-items: flex-end !important;
  gap: 2px !important;
`;

const ItemCountMobile = styled.span`
  font-size: 11px !important;
  font-weight: 500 !important;
  color: rgba(17, 24, 39, 0.6) !important;

  @media (min-width: 768px) {
    font-size: 12px !important;
  }
`;

const CompactSavingsContainer = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 4px !important;
  margin-top: 8px !important;
  padding: 4px 8px !important;
  background: linear-gradient(
    135deg,
    rgba(34, 197, 94, 0.1),
    rgba(22, 163, 74, 0.1)
  ) !important;
  border-radius: 4px !important;
  border: 1px solid rgba(34, 197, 94, 0.2) !important;

  @media (min-width: 768px) {
    padding: 6px 10px !important;
    border-radius: 6px !important;
    margin-top: 10px !important;
  }
`;

const SavingsIconSmall = styled.div`
  width: 12px !important;
  height: 12px !important;
  background: #22c55e !important;
  color: white !important;
  border-radius: 50% !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  font-size: 8px !important;
  font-weight: 700 !important;

  @media (min-width: 768px) {
    width: 14px !important;
    height: 14px !important;
    font-size: 9px !important;
  }
`;

const SavingsTextSmall = styled.div`
  font-size: 10px !important;
  font-weight: 600 !important;
  color: #15803d !important;
  letter-spacing: 0.02em !important;
  text-transform: uppercase !important;

  @media (min-width: 768px) {
    font-size: 11px !important;
  }
`;
