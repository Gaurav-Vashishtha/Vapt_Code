import React, { useMemo } from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import shallow from "zustand/shallow";
import { formatCurrency } from "../../../utilities/otpUtils";
import Skeleton, { SkeletonTheme } from "react-loading-skeleton";
import "react-loading-skeleton/dist/skeleton.css";

// OrderSummaryCard Component
const OrderSummaryCard = ({ theme }) => {
  // Read currentCartData directly from otpStore instead of CartStore
  const { currentCartData, isCartReady } = useOtpStore(
    (state) => ({
      currentCartData: state.currentCartData,
      isCartReady: state.isCartReady,
    }),
    shallow
  );

  const cartState = currentCartData || {};

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

  const totalQuantity = cartState.item_count || 0;
  const currencyCode = cartState.currency || "INR";
  const totalPrice = (cartState.total_price || 0) / 100;
  const summaryLoading = !isCartReady;

  const LoadingSkeleton = ({ count }) => (
    <SkeletonTheme
      baseColor="var(--skeleton-base, rgba(255, 255, 255, 0.1))"
      highlightColor="var(--skeleton-highlight, rgba(255, 255, 255, 0.2))"
    >
      <p>
        <Skeleton count={count} />
      </p>
    </SkeletonTheme>
  );

  return (
    <StyledOrderSummaryCard theme={theme}>
      <OrderSummaryHeader>
        <h3>Order summary</h3>
        <Arrow>&gt;</Arrow>
      </OrderSummaryHeader>
      {summaryLoading ? (
        <LoadingSkeleton count={4} />
      ) : (
        <>
          {" "}
          {productData.map((product, index) => (
            <OrderDetails key={index}>
              <ProductImageWrapper>
                <img
                  src={product.imageSrc}
                  alt="Product"
                  style={{ width: "100%", height: "100%", objectFit: "cover" }}
                />
              </ProductImageWrapper>
              <ProductInfo>
                <ProductName>{product.name}</ProductName>
                <ProductQuantity>
                  Qty: {product.quantity}{" "}
                  <span style={{ fontSize: "12px", opacity: 0.8 }}>
                    (× {formatCurrency(product.price, currencyCode)})
                  </span>
                </ProductQuantity>
              </ProductInfo>
              <ProductPrice>
                {formatCurrency(product.price * product.quantity, currencyCode)}
              </ProductPrice>
            </OrderDetails>
          ))}
        </>
      )}

      {summaryLoading ? (
        <LoadingSkeleton count={1} />
      ) : (
        <TotalSection>
          <TotalItems>{totalQuantity} items</TotalItems>
          <TotalPrice>{formatCurrency(totalPrice, currencyCode)}</TotalPrice>
        </TotalSection>
      )}
    </StyledOrderSummaryCard>
  );
};

export default OrderSummaryCard;

// ----- Styled Components -----

const StyledOrderSummaryCard = styled.div`
  background-color: ${(props) => props.theme.cardBg};
  border-radius: 12px;
  padding: 16px;
  margin-bottom: 16px;
`;

const OrderSummaryHeader = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;

  h3 {
    margin: 0;
    font-size: 16px;
  }
`;

const Arrow = styled.span`
  color: #666;
`;

const OrderDetails = styled.div`
  display: flex;
  gap: 12px;
  align-items: center;
  margin-bottom: 8px;
`;

const ProductImageWrapper = styled.div`
  width: 48px;
  height: 48px;
  border-radius: 50%;
  overflow: hidden;
`;

const ProductInfo = styled.div`
  flex: 1;
`;

const ProductName = styled.div`
  font-size: 14px;
  font-weight: 500;
`;

const ProductQuantity = styled.div`
  font-size: 12px;
  color: #666;
  margin-top: 4px;
`;

const ProductPrice = styled.div`
  font-weight: 600;
`;

const TotalSection = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid rgba(0, 0, 0, 0.1);
`;

const TotalItems = styled.div`
  font-size: 14px;
  font-weight: 600;
`;

const TotalPrice = styled.div`
  font-size: 16px;
  font-weight: 700;
`;
