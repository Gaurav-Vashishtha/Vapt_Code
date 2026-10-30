import React, { useState, useEffect } from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import Skeleton from "react-loading-skeleton";
import "react-loading-skeleton/dist/skeleton.css";
import shallow from "zustand/shallow";
import CodkingButton from "../CommonComponent/codKingButton";
import StickyFooterWithSummary from "../MobileLayout/MobileStickyFooterWithSummary";
import { CreditCard, Banknote, Tag, Check } from "lucide-react";

// Import common utilities
import {
  convertFloatToInt,
  initializeCartAndRules,
  handleRuleSelection,
  calculateRulePrice,
  generateRuleDescription,
  hasRuleDiscount,
  hasOrderSummaryDiscount,
  handlePaymentSubmit,
} from "../CommonComponent/paymentOptionsUtils";

import {
  getDescBundle,
  getPriceBundle,
  handlePartialPaymentSubmitBundle,
} from "../CommonComponent/partialPaymentBundleFuntions";
import {
  formatCurrency,
  getCurrentStep,
  getSessionValue,
} from "../../../utilities/otpUtils";

const SkeletonLoaderCODK = styled(Skeleton)`
  width: 500px !important;
  height: 60px !important;
  margin-bottom: 12px !important;
  border-radius: 12px !important;
  @media (max-width: 480px) {
    width: 100% !important;
  }
`;

const Container = styled.div`
  display: flex !important;
  flex-direction: column !important;
  gap: 10px !important;
  padding: 10px !important;
  max-width: 700px !important;
  margin: auto !important;
  @media (max-width: 480px) {
    padding: 16px !important;
  }
`;

const Title = styled.h2`
  font-size: 24px !important;
  font-weight: 700 !important;
  text-align: center !important;
  color: #1f2937 !important;
  margin: 0 0 8px 0 !important;
`;

const Subtitle = styled.p`
  font-size: 14px !important;
  color: #6b7280 !important;
  text-align: center !important;
  margin: 0 0 10px 0 !important;
`;
const Card = styled.div`
  width: 100% !important;
  background: #ffffff !important;
  border-radius: 16px !important;
  overflow: hidden !important;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1),
    0 2px 4px -1px rgba(0, 0, 0, 0.06) !important;
  border: 1px solid #e5e7eb !important;
  max-height: 420px !important;
  overflow-y: auto !important;

  @media (max-width: 480px) {
    max-height: 500px !important;
    border-radius: 12px !important;
  }
`;

const OptionWrapper = styled.div`
  display: flex !important;
  flex-direction: column !important;
`;

const Divider = styled.div`
  width: 100% !important;
  height: 1px !important;
  background-color: #f3f4f6 !important;
`;

const RuleTitle = styled.div`
  font-size: 16px !important;
  font-weight: 600 !important;
  color: #1f2937 !important;
  display: flex !important;
  align-items: center !important;
  white-space: normal !important;
  overflow: visible !important;
  text-overflow: unset !important;
  line-height: 1.4 !important;
`;

const RuleDesc = styled.div`
  font-size: 12px !important;
  color: #6b7280 !important;
  margin-top: 6px !important;
  white-space: normal !important;
  overflow: visible !important;
  text-overflow: unset !important;
  line-height: 1.4 !important;
`;

const ErrorMessage = styled.p`
  color: #dc2626 !important;
  font-size: 14px !important;
  margin-top: 10px !important;
  text-align: center !important;
  background-color: #fef2f2 !important;
  border: 1px solid #fecaca !important;
  border-radius: 8px !important;
  padding: 12px 16px !important;
`;

const CodBadge = styled.div`
  display: inline-flex !important;
  align-items: center !important;
  background-color: #dc2626 !important;
  color: white !important;
  font-size: 10px !important;
  font-weight: 600 !important;
  padding: 4px 8px !important;
  border-radius: 6px !important;
  margin-left: 8px !important;
`;

const DiscountBadge = styled.div`
  display: inline-flex !important;
  align-items: center !important;
  background-color: #059669 !important;
  color: white !important;
  font-size: 10px !important;
  font-weight: 600 !important;
  padding: 4px 8px !important;
  border-radius: 6px !important;
  margin-left: 8px !important;
`;

const Option = styled.div`
  display: flex !important;
  align-items: flex-start !important;
  justify-content: space-between !important;
  width: 100% !important;
  box-sizing: border-box !important;
  padding: 20px 24px !important;
  cursor: pointer !important;
  transition: all 0.2s ease !important;
  position: relative !important;

  background-color: ${(props) => (props.selected ? "#f0f9ff" : "#ffffff")};
  border-left: ${(props) =>
    props.selected ? "4px solid #0ea5e9" : "4px solid transparent"};

  &:hover {
    background-color: ${(props) => (props.selected ? "#e0f2fe" : "#f8fafc")};
    transform: translateX(2px);
  }

  &:active {
    transform: translateX(1px);
  }

  @media (max-width: 480px) {
    padding: 16px 20px !important;
  }
`;

const Left = styled.div`
  display: flex !important;
  flex-direction: column !important;
  flex: 1 !important;
  min-width: 0 !important;
  padding-right: 16px !important;
`;

const Price = styled.div`
  font-size: 16px !important;
  font-weight: 700 !important;
  text-align: right !important;
  color: #1f2937 !important;
  min-width: 100px !important;
  flex-shrink: 0 !important;

  span {
    display: block !important;
    font-size: 10px !important;
    font-weight: 400 !important;
    color: #9ca3af !important;
    margin-top: 2px !important;
  }
`;

const BlockInteractionWrapper = styled.div`
  ${(props) =>
    props.disabled &&
    `
    pointer-events: none;
    opacity: 0.6;
  `}
`;

const IconWrapper = styled.span`
  display: inline-flex;
  align-items: center;
  justify-content: center;
  margin-right: 10px;
  padding: 8px;
  background-color: ${(props) => (props.selected ? "#0ea5e9" : "#e5e7eb")};
  color: ${(props) => (props.selected ? "#ffffff" : "#6b7280")};
  border-radius: 8px;
  transition: all 0.2s ease;
  font-size: 16px;
`;

const SelectionIndicator = styled.div`
  // position: absolute !important;
  // top: 16px !important;
  // right: 20px !important;
  // width: 20px !important;
  // height: 20px !important;
  // border-radius: 50% !important;
  // background-color: ${(props) =>
    props.selected ? "#0ea5e9" : "transparent"};
  // border: 2px solid ${(props) => (props.selected ? "#0ea5e9" : "#d1d5db")};
  // display: flex !important;
  // align-items: center !important;
  // justify-content: center !important;
  // transition: all 0.2s ease !important;

  // @media (max-width: 480px) {
  //   top: 14px !important;
  //   right: 16px !important;
  //   width: 18px !important;
  //   height: 18px !important;
  // }
`;

const CheckIcon = styled(Check)`
  width: 12px !important;
  height: 12px !important;
  color: white !important;
  opacity: ${(props) => (props.selected ? 1 : 0)};
  transition: opacity 0.2s ease !important;
`;

const CreateCartComponent = () => {
  const [ruleSets, setRuleSets] = useState([]);
  const [selectedRule, setSelectedRule] = useState(null);
  const [error, setError] = useState("");
  const [cartTotal, setCartTotal] = useState(0);
  const [isFullPercentage, setIsFullPercentage] = useState(true);
  const [isCOD, setIsCOD] = useState(true);
  const [isPartialLoading, setIsPartialLoading] = useState(false);
  const [isLoaderLoading, setIsLoaderLoading] = useState(true);

  const currencyCode = window?.Shopify?.currency?.active || "INR";
  const settings = getSessionValue("settingSession");

  const {
    setStep,
    setIsPartialPaymentCartReadyAndUpdated,
    handleSkip,
    isPartialCartRevertToOriginalCartCompleted,
    isCartManipulationProcessCompleted,
    orderSummary,
    isCreatingCarts,
    setOrderSummary,
    isCartReady,
  } = useOtpStore(
    (state) => ({
      setStep: state.setStep,
      setIsPartialPaymentCartReadyAndUpdated:
        state.setIsPartialPaymentCartReadyAndUpdated,
      otpData: state.otpData,
      setOtpData: state.setOtpData,
      handleSkip: state.handleSkip,
      isCartReady: state.isCartReady,
      setIsCartReady: state.setIsCartReady,
      isPartialCartRevertToOriginalCartCompleted:
        state.isPartialCartRevertToOriginalCartCompleted,
      orderSummary: state.orderSummary,
      setOrderSummary: state.setOrderSummary,
      partialCartData: state.partialCartData,
      setPartialCartData: state.setPartialCartData,
      isCartManipulationProcessCompleted:
        state.isCartManipulationProcessCompleted,
      setIsCartManipulationProcessCompleted:
        state.setIsCartManipulationProcessCompleted,
      isCreatingCarts: state.isCreatingCarts,
    }),
    shallow
  );

  useEffect(() => {
    const initialize = async () => {
      setIsLoaderLoading(true);
      await initializeCartAndRules(
        setCartTotal,
        setRuleSets,
        setSelectedRule,
        setIsFullPercentage,
        setIsCOD,
        setIsLoaderLoading,
        orderSummary // Pass orderSummary here
      );
    };

    initialize();
  }, [
    isCartManipulationProcessCompleted,
    isPartialCartRevertToOriginalCartCompleted,
    orderSummary?.totalPrice,
    orderSummary?.totalQuantity,
  ]);

  useEffect(() => {
    if (ruleSets.length > 0 && !selectedRule) {
      setSelectedRule(ruleSets[0].id);
      const is100Percent =
        ruleSets[0].amount === "100.0" &&
        ruleSets[0].amount_type === "percentage";
      setIsFullPercentage(is100Percent);
    }
  }, [ruleSets]);

  useEffect(() => {
    if (!isLoaderLoading && ruleSets.length === 0) {
      const goToNextStep = async () => {
        try {
          setIsPartialPaymentCartReadyAndUpdated(true);
          const currentStep = await getCurrentStep();
          setStep(currentStep);
        } catch (err) {
          console.error("Error getting current step:", err);
        }
      };

      goToNextStep();
    }
  }, [ruleSets, isLoaderLoading]);

  const handleSelect = (id) => {
    handleRuleSelection(
      id,
      ruleSets,
      setSelectedRule,
      setError,
      setIsCOD,
      setIsFullPercentage
    );
  };

  const getPrice = (rule) => {
    return calculateRulePrice(rule, cartTotal, orderSummary, currencyCode);
  };

  const getDesc = (rule) => {
    return generateRuleDescription(
      rule,
      cartTotal,
      orderSummary,
      currencyCode,
      getPrice
    );
  };

  const getIconForRule = (rule, isSelected) => {
    if (rule.amount === "100.0" && rule.amount_type === "percentage")
      return (
        <IconWrapper selected={isSelected}>
          <CreditCard size={18} />
        </IconWrapper>
      );

    if (rule.amount_type === "fixed")
      return (
        <IconWrapper selected={isSelected}>
          <Tag size={18} />
        </IconWrapper>
      );

    return (
      <IconWrapper selected={isSelected}>
        <Banknote size={18} />
      </IconWrapper>
    );
  };

  const handleSubmit = async () => {
    const partialPaymentFlowVersion = settings?.partialPaymentFlowVersion;
    if (partialPaymentFlowVersion === 2) {
      await handlePartialPaymentSubmitBundle(
        selectedRule,
        ruleSets,
        setIsPartialLoading,
        setError,
        setIsPartialPaymentCartReadyAndUpdated,
        setStep,
        cartTotal,
        orderSummary
      );
    } else {
      await handlePaymentSubmit(
        isFullPercentage,
        isCOD,
        selectedRule,
        ruleSets,
        setIsPartialLoading,
        setError,
        setIsPartialPaymentCartReadyAndUpdated,
        handleSkip,
        setStep,
        cartTotal,
        orderSummary
      );
    }
  };

  return (
    <Container>
      <Title>Choose Your Payment Option</Title>
      {/* <Subtitle>Select the payment method that works best for you</Subtitle> */}

      <BlockInteractionWrapper disabled={isPartialLoading || !isCartReady}>
        <Card>
          <OptionWrapper>
            {!isCartReady || ruleSets.length === 0 ? (
              <OptionWrapper>
                <SkeletonLoaderCODK count={3} />
              </OptionWrapper>
            ) : (
              ruleSets.map((rule, index) => {
                const isSelected = selectedRule === rule.id;
                const ruleHasDiscount = hasRuleDiscount(rule);
                const orderHasDiscount = hasOrderSummaryDiscount(orderSummary);

                return (
                  <React.Fragment key={rule.id}>
                    <Option
                      selected={isSelected}
                      onClick={() => handleSelect(rule.id)}
                    >
                      <Left>
                        <RuleTitle>
                          {getIconForRule(rule, isSelected)}
                          {rule.rule_name}
                          {/* COD badge */}
                          {rule.amount_type === "cod" && rule.amount > 0 && (
                            <CodBadge>
                              {formatCurrency(
                                parseFloat(rule.amount),
                                currencyCode
                              )}{" "}
                              COD fee
                            </CodBadge>
                          )}
                          {/* Rule Discount badge */}
                          {ruleHasDiscount && (
                            <DiscountBadge>
                              {(() => {
                                const cartData =
                                  useOtpStore.getState()?.currentCartData || {};

                                const originalCartTotalDecimal =
                                  typeof cartData?.original_total_price ===
                                  "number"
                                    ? cartData.original_total_price / 100
                                    : ((cartData?.total_price || 0) +
                                        (cartData?.total_discount || 0)) /
                                      100;

                                const lineLevelDiscountDecimal = (
                                  cartData?.items || []
                                ).reduce((sum, item) => {
                                  const hasLineLevelDiscounts =
                                    item?.line_level_discount_allocations &&
                                    item.line_level_discount_allocations
                                      .length > 0;
                                  if (!hasLineLevelDiscounts) return sum;

                                  const cents =
                                    item?.line_level_total_discount ||
                                    (item?.line_level_discount_allocations ||
                                      []).reduce((s, alloc) => {
                                      return s + (alloc?.amount || 0);
                                    }, 0);

                                  return sum + cents / 100;
                                }, 0);

                                const existingOrderLevelDiscountDecimal = (
                                  (cartData?.cart_level_discount_applications ||
                                    []).reduce((sum, d) => {
                                    return (
                                      sum + (d?.total_allocated_amount || 0)
                                    );
                                  }, 0) / 100
                                );

                                const ruleDiscountValueNum = parseFloat(
                                  String(rule?.discount_value ?? "0"),
                                );
                                const ruleDiscountType =
                                  rule?.discount_type || "";
                                const ruleDiscountCode = (
                                  rule?.discount_code || ""
                                ).trim();

                                let ruleOrderLevelDiscount = 0;
                                if (
                                  ruleDiscountCode &&
                                  ruleDiscountValueNum > 0
                                ) {
                                  if (ruleDiscountType === "percentage") {
                                    const base = Math.max(
                                      0,
                                      originalCartTotalDecimal -
                                        lineLevelDiscountDecimal,
                                    );
                                    ruleOrderLevelDiscount =
                                      (base * ruleDiscountValueNum) / 100;
                                  } else {
                                    ruleOrderLevelDiscount = ruleDiscountValueNum;
                                  }
                                }

                                const effectiveOrderLevelDiscount = Math.max(
                                  existingOrderLevelDiscountDecimal || 0,
                                  ruleOrderLevelDiscount || 0,
                                );

                                const ruleWins =
                                  ruleOrderLevelDiscount >=
                                  existingOrderLevelDiscountDecimal;

                                // If rule is percentage and wins, keep showing %;
                                // otherwise show the effective fixed amount.
                                if (
                                  rule.discount_type === "percentage" &&
                                  ruleWins
                                ) {
                                  return `Save ${convertFloatToInt(
                                    rule.discount_value,
                                  )}%`;
                                }

                                return `Save ${formatCurrency(
                                  effectiveOrderLevelDiscount,
                                  currencyCode,
                                )}`;
                              })()}
                            </DiscountBadge>
                          )}
                        </RuleTitle>

                        {!(rule.amount_type === "cod" && rule.amount == 0) && (
                          <RuleDesc>
                            {" "}
                            {settings?.partialPaymentFlowVersion === 2
                              ? getDescBundle(rule)
                              : getDesc(rule)}
                          </RuleDesc>
                        )}
                      </Left>

                      <div
                        style={{
                          display: "flex",
                          alignItems: "center",
                          gap: "12px",
                        }}
                      >
                        <Price>
                          {settings?.partialPaymentFlowVersion === 2
                            ? getPriceBundle(rule)
                            : getPrice(rule)}

                          <span>{settings?.preV2PartialTaxText || ""}</span>
                        </Price>

                        <SelectionIndicator selected={isSelected}>
                          <CheckIcon selected={isSelected} />
                        </SelectionIndicator>
                      </div>
                    </Option>
                    {index < ruleSets.length - 1 && <Divider />}
                  </React.Fragment>
                );
              })
            )}
          </OptionWrapper>
        </Card>
      </BlockInteractionWrapper>

      {error && <ErrorMessage>{error}</ErrorMessage>}
      {isLoaderLoading === false && (
        <>
          {window.innerWidth <= 768 ? (
            <StickyFooterWithSummary>
              <CodkingButton
                onClick={handleSubmit}
                disabled={!isCartReady}
                loading={isPartialLoading || isCreatingCarts}
                fullWidth
              >
                Continue to Payment
              </CodkingButton>
            </StickyFooterWithSummary>
          ) : (
            <CodkingButton
              onClick={handleSubmit}
              disabled={!isCartReady}
              loading={isPartialLoading || isCreatingCarts}
            >
              Continue to Payment
            </CodkingButton>
          )}
        </>
      )}
    </Container>
  );
};

export default CreateCartComponent;
