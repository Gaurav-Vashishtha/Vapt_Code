import React, { useMemo } from "react";
import styled from "styled-components";
import { formatCurrency } from "../../../utilities/otpUtils";
import useOtpStore from "../../../stores/otpStore";
import shallow from "zustand/shallow";

const SlidingOrderSummary = ({
  isSliderOpen,
  setSliderOpen,
  decodeHTMLEntities,
}) => {
  // Read currentCartData directly from otpStore instead of CartStore
  const { currentCartData, orderSummary } = useOtpStore(
    (state) => ({
      currentCartData: state.currentCartData,
      orderSummary: state.orderSummary,
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
  const subtotalPrice = (cartState.original_total_price || 0) / 100;
  const discountedPrice = (cartState.total_price || 0) / 100;
  const discountAmount = (cartState.total_discount || 0) / 100;
  const hasDiscount = (cartState.total_discount || 0) > 0;
  const firstCartDiscount = cartState.cart_level_discount_applications?.[0];
  const discountTitle =
    firstCartDiscount?.title || cartState.discount_codes?.[0]?.code || "";
  return (
    <>
      {isSliderOpen && (
        <div
          style={{
            position: "fixed",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            zIndex: 100014,
          }}
          onClick={() => setSliderOpen(false)}
        >
          <ModalContainer
            isOpen={isSliderOpen}
            onClick={(e) => e.stopPropagation()} // prevent inner clicks from closing
          >
            <ScrollableContent>
              {/* Header */}
              <Header>
                <HeaderContent>
                  <Title>Order Summary</Title>
                  <ItemCount>{totalQuantity} item(s)</ItemCount>
                  <CloseButton onClick={() => setSliderOpen(false)}>
                    &times;
                  </CloseButton>
                </HeaderContent>
              </Header>
              {/* Product List */}
              <ProductSection>
                {productData?.map((product, index) => {
                  const decodedName = decodeHTMLEntities(product.name);
                  return (
                    <ProductItem key={index}>
                      <ProductImage src={product.imageSrc} alt={decodedName} />
                      <ProductDetails>
                        <ProductName>{decodedName}</ProductName>
                        <ProductQuantity>
                          Qty: {product.quantity}
                        </ProductQuantity>
                      </ProductDetails>
                      <ProductPrice>
                        {formatCurrency(product.price, currencyCode)}
                      </ProductPrice>
                    </ProductItem>
                  );
                })}
              </ProductSection>
              <Separator />
              {/* Pricing Details */}
              <TotalSection>
                <TotalRow>
                  <span>Subtotal</span>
                  <span>{formatCurrency(subtotalPrice, currencyCode)}</span>
                </TotalRow>

                {/* Discount Row */}
                {hasDiscount && (
                  <>
                    <DiscountRow>
                      <DiscountLabel>
                        <span>Discount</span>
                        <DiscountBadge>
                          {firstCartDiscount?.value_type === "percentage"
                            ? `${firstCartDiscount?.value}% OFF`
                            : `FLAT ${formatCurrency(
                                discountAmount,
                                currencyCode
                              )} OFF`}
                        </DiscountBadge>
                        {discountTitle ? (
                          <DiscountCode title={discountTitle}>
                            ({discountTitle.toUpperCase()})
                          </DiscountCode>
                        ) : null}
                      </DiscountLabel>
                      <DiscountAmount>
                        -{formatCurrency(discountAmount, currencyCode)}
                      </DiscountAmount>
                    </DiscountRow>

                    {/* Total Savings */}
                    <TotalSavingsRow>
                      <SavingsContainer>
                        <SavingsIcon>
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            viewBox="0 0 20 20"
                            fill="currentColor"
                          >
                            <path
                              fillRule="evenodd"
                              d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                              clipRule="evenodd"
                            />
                          </svg>
                        </SavingsIcon>
                        <SavingsText>
                          TOTAL SAVINGS{" "}
                          {formatCurrency(discountAmount, currencyCode)}
                        </SavingsText>
                      </SavingsContainer>
                    </TotalSavingsRow>
                  </>
                )}
              </TotalSection>
              <BlackSeparator />
              {/* Grand Total */}
              <GrandTotal>
                <span>Grand Total</span>
                <GrandTotalPrice hasDiscount={hasDiscount}>
                  <FinalPrice>
                    {formatCurrency(discountedPrice, currencyCode)}
                  </FinalPrice>
                </GrandTotalPrice>
              </GrandTotal>
            </ScrollableContent>
          </ModalContainer>
        </div>
      )}
    </>
  );
};

export default SlidingOrderSummary;

// Styled Components

const Backdrop = styled.div`
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 100014; // just below modal
  background: rgba(0, 0, 0, 0.3);
  backdrop-filter: blur(2px);
  transition: opacity 0.3s ease;
`;

const ModalContainer = styled.div`
  position: fixed;
  bottom: ${({ isOpen }) => (isOpen ? "0" : "-100%")}; /* Bottom Slide */
  left: 0;
  height: 50%; /* Take half of the screen height */
  width: 100%; /* Full width for mobile or bottom sheet feel */
  background-color: #f9f9f9;
  border-top-left-radius: 16px;
  border-top-right-radius: 16px;
  box-shadow: 0 -4px 10px rgba(0, 0, 0, 0.1);
  transition: bottom 0.35s ease-in-out;
  z-index: 9999;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  z-index: 100015 !important;
  @media (min-width: 768px) {
    z-index: 100015 !important;
    position: fixed;
    top: 0;
    left: ${({ isOpen }) =>
      isOpen ? "0" : "-400px"}; /* Left Side Animation */
    height: 100%;
    width: 340px;
    background-color: #f9f9f9; /* Matched Background */
    border-radius: 0 12px 12px 0;
    box-shadow: 4px 0 10px rgba(0, 0, 0, 0.1);
    transition: left 0.3s ease-in-out;
    z-index: 9999;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
`;

const ScrollableContent = styled.section`
  overflow-y: auto;
  flex-grow: 1;
  padding: 20px;
`;

const Header = styled.div`
  padding: 16px 20px;
  border-bottom: 1px solid #e5e7eb;
  display: flex;
  justify-content: space-between;
  align-items: center;
`;

const HeaderContent = styled.div`
  display: flex;
  align-items: center;
  width: 100%;
`;

const Title = styled.span`
  font-size: 18px;
  font-weight: bold;
  color: black;
`;

const ItemCount = styled.span`
  font-size: 14px;
  margin-left: 10px;
  color: gray;
`;

const CloseButton = styled.button`
  background: none;
  border: none;
  font-size: 22px;
  font-weight: bold;
  cursor: pointer;
  margin-left: auto;
  color: black;
`;

const ProductSection = styled.div`
  padding: 16px;
`;

const ProductItem = styled.div`
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 12px;
`;

const ProductImage = styled.img`
  width: 50px;
  height: 50px;
  border-radius: 50%;
  object-fit: cover;
  border: 1px solid #ddd;
`;

const ProductDetails = styled.div`
  flex-grow: 1;
`;

const ProductName = styled.p`
  font-size: 14px;
  font-weight: 600;
  margin: 0;
  color: black;
  white-space: normal;
  word-wrap: break-word;
  overflow-wrap: break-word;
  line-height: 1.3;
`;

const ProductQuantity = styled.p`
  font-size: 12px;
  color: gray;
  margin: 4px 0 0;
`;

const ProductPrice = styled.div`
  font-size: 16px;
  font-weight: bold;
  color: black;
`;

const Separator = styled.div`
  margin: 10px 0;
  border-top: 1px solid rgba(0, 0, 0, 0.2); /* Light Underline */
`;

const BlackSeparator = styled.div`
  display: block !important;
  margin: 10px 0;
  border-top: 1px solid black; /* 🔥 Black Underline Before Grand Total */
`;

const TotalSection = styled.div`
  padding: 12px 16px;
`;

const TotalRow = styled.p`
  display: flex;
  justify-content: space-between;
  margin: 0;
  font-size: 14px;
  color: black;
  margin-bottom: 8px;
  .tax-text {
    font-size: 12px;
    color: gray;
  }
`;

// New discount-related styled components
const DiscountRow = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 8px;
  padding: 8px 0;
  background: rgba(34, 197, 94, 0.05);
  border-radius: 6px;
  padding: 8px 12px;
`;

const DiscountLabel = styled.div`
  display: flex;
  flex-direction: column;
  gap: 4px;
  flex: 1;

  span {
    font-size: 14px;
    color: #15803d;
    font-weight: 500;
  }
`;

const DiscountCode = styled.div`
  font-size: 10px;
  font-weight: 500;
  color: rgba(17, 24, 39, 0.6);
  letter-spacing: 0.05em;
  text-transform: uppercase;
`;

const DiscountBadge = styled.div`
  background: linear-gradient(135deg, #10b981, #059669);
  color: white;
  font-size: 9px;
  font-weight: 600;
  padding: 2px 6px;
  border-radius: 4px;
  letter-spacing: 0.02em;
  text-transform: uppercase;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  display: inline-block;
  margin-top: 2px;
  width: fit-content;
`;

const DiscountAmount = styled.div`
  font-size: 14px;
  font-weight: 600;
  color: #15803d;
`;

const TotalSavingsRow = styled.div`
  margin: 12px 0;
`;

const SavingsContainer = styled.div`
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 12px;
  background: linear-gradient(
    135deg,
    rgba(34, 197, 94, 0.1),
    rgba(22, 163, 74, 0.1)
  );
  border-radius: 8px;
  border: 1px solid rgba(34, 197, 94, 0.2);
`;

const SavingsIcon = styled.div`
  width: 16px;
  height: 16px;
  color: #22c55e;
  flex-shrink: 0;

  svg {
    width: 100%;
    height: 100%;
  }
`;

const SavingsText = styled.div`
  font-size: 12px;
  font-weight: 600;
  color: #15803d;
  letter-spacing: 0.02em;
  text-transform: uppercase;
`;

const GrandTotal = styled(TotalRow)`
  font-size: 18px;
  font-weight: bold;
  padding-top: 12px;
  margin-bottom: 0;
`;

const GrandTotalPrice = styled.div`
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: ${(props) => (props.hasDiscount ? "4px" : "0")};
`;

const OriginalGrandTotal = styled.div`
  font-size: 14px;
  font-weight: 500;
  color: rgba(17, 24, 39, 0.5);
  text-decoration: line-through;
  text-decoration-color: rgba(239, 68, 68, 0.8);
  text-decoration-thickness: 1.5px;
`;

const FinalPrice = styled.div`
  font-size: 18px;
  font-weight: bold;
  color: black;
`;
