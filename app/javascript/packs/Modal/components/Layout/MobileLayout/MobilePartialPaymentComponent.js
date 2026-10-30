import React, { useEffect, useState } from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import Skeleton from "react-loading-skeleton";
import "react-loading-skeleton/dist/skeleton.css";
import shallow from "zustand/shallow";
import CodkingButton from "../CommonComponent/codKingButton";

import {
  shinyBackboneEffectWithColor,
  shinyBadgeEffectWithColor,
} from "../DesktopLayout/Styles/shinyBackbone";
import StickyFooter from "./MobileFooterSection";

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
  getCurrentStep,
  getSessionValue,
  debugLog,
  formatCurrency,
} from "../../../utilities/otpUtils";
import {
  getDescBundle,
  getPriceBundle,
  handlePartialPaymentSubmitBundle,
} from "../CommonComponent/partialPaymentBundleFuntions";

const MobilePartialPaymentComponentContainer = styled.div`
  margin-top: 9%;
  padding-bottom: 100px;
`;

const RecommendedText = styled.div`
  font-size: 16px;
  font-weight: 600;
  color: #111827;
  margin-bottom: 16px;
  text-align: center;
`;

const PaymentOptionsContainer = styled.div`
  border: 1px solid #e5e7eb;
  border-radius: 12px;
  overflow: hidden;
  background-color: white;
`;

const PaymentOptionLabel = styled.label`
  display: block;
  position: relative;
  cursor: pointer;
`;

const PaymentOptionInput = styled.input`
  position: absolute;
  opacity: 0;
  pointer-events: none;
  z-index: -10;
  width: 100%;
  height: 100%;
`;

const PaymentOptionContent = styled.div`
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px;
  min-height: 48px;
  transition: all 200ms;
  background-color: ${(props) => (props.isSelected ? "#dbeafe" : "white")};
  border: ${(props) =>
    props.isSelected ? "2px solid #3b82f6" : "1px solid transparent"};
  border-radius: ${(props) => (props.isSelected ? "8px" : "0")};
  border-top: ${(props) =>
    props.hasBorderTop && !props.isSelected ? "1px solid #f3f4f6" : "none"};

  &:hover {
    background-color: ${(props) => (props.isSelected ? "#bfdbfe" : "#f3f4f6")};
  }

  &:active {
    background-color: ${(props) => (props.isSelected ? "#bfdbfe" : "#f3f4f6")};
  }
`;

const PaymentOptionName = styled.span`
  display: block;
  font-size: 14px;
  font-weight: 600;
  color: #111827;
  white-space: normal;
  word-break: break-word;
  overflow-wrap: break-word;
  line-height: 1.3;
`;

const CheckmarkIcon = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
  width: 16px;
  height: 16px;
  border-radius: 50%;
  border: 2px solid ${(props) => (props.isSelected ? "#3b82f6" : "#d1d5db")};
  background-color: ${(props) =>
    props.isSelected ? "#3b82f6" : "transparent"};
  flex-shrink: 0;
  transition: all 200ms;

  ${(props) =>
    props.isSelected &&
    `
    &::after {
      content: '✓';
      color: white;
      font-size: 10px;
      font-weight: 600;
    }
  `}
`;

const ErrorMessage = styled.p`
  color: red !important;
  font-size: 14px !important;
  margin-top: 10px !important;
  text-align: center !important;
`;

const DiscountTagBadge = styled.span`
  background-color: #d1fae5;
  color: #065f46;
  padding: 2px 6px;
  font-size: 12px;
  border-radius: 4px;
  ${shinyBadgeEffectWithColor("#d1fae5")}
`;

const CodFeeBadge = styled.span`
  background-color: #fee2e2;
  color: #b91c1c;
  padding: 2px 6px;
  font-size: 12px;
  border-radius: 4px;
  ${shinyBadgeEffectWithColor("#fee2e2")}
`;

const BlockInteractionWrapper = styled.div`
  ${(props) =>
    props.disabled &&
    `
    pointer-events: none;
    opacity: 0.6;
  `}
`;

const OptionWrapper = styled.div`
  display: flex !important;
  flex-direction: column !important;
`;

const SkeletonLoaderCODK = styled(Skeleton)`
  width: 500px !important;
  height: 40px !important;
  margin-bottom: 6px !important;
  display: flex !important;
  justify-content: center !important;
  align-items: center !important;
  @media (max-width: 480px) {
    width: 100% !important;
  }
`;

const MobilePartialPaymentComponent = () => {
  const [selectedOption, setSelectedOption] = useState("");
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
    isCartReady,
    orderSummary,
    isCreatingCarts,
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
      partialCartData: state.partialCartData,
      setPartialCartData: state.setPartialCartData,
      isCreatingCarts: state.isCreatingCarts,
    }),
    shallow
  );

  useEffect(() => {
    if (!isCartReady) {
      return () => {}; // Return no-op cleanup function
    }

    let isMounted = true;

    const initialize = async () => {
      // If we're already initialized or in the middle of it, we still want to ensure rules are ready
      if (!isMounted) return;
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

    return () => {
      isMounted = false;
    };
  }, [
    isCartReady,
    isPartialCartRevertToOriginalCartCompleted,
    orderSummary?.totalPrice,
    orderSummary?.totalQuantity,
  ]);

  useEffect(() => {
    debugLog("ruleSets", ruleSets);
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
    <MobilePartialPaymentComponentContainer>
      {!isCartReady ? (
        <MobilePartialPaymentComponentContainer>
          <OptionWrapper>
            <SkeletonLoaderCODK count={3} />
          </OptionWrapper>
        </MobilePartialPaymentComponentContainer>
      ) : (
        <BlockInteractionWrapper disabled={isPartialLoading}>
          <br />
          {ruleSets.length === 0 ? (
            <ErrorMessage>No payment options available</ErrorMessage>
          ) : (
            ruleSets.length > 0 && (
              <div style={{ marginTop: "13%" }}>
                <RecommendedText>Choose a payment option</RecommendedText>
                <PaymentOptionsContainer>
                  {ruleSets.map((rule, index) => {
                    const ruleHasDiscount = hasRuleDiscount(rule);
                    const orderHasDiscount =
                      hasOrderSummaryDiscount(orderSummary);

                    return (
                      <PaymentOptionLabel key={rule.id}>
                        <PaymentOptionInput
                          type="radio"
                          name="rule-option"
                          value={rule.id}
                          checked={selectedRule === rule.id}
                          onChange={() => handleSelect(rule.id)}
                        />

                        <PaymentOptionContent
                          isSelected={selectedRule === rule.id}
                          hasBorderTop={index > 0}
                        >
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <PaymentOptionName>
                              {rule.rule_name}
                            </PaymentOptionName>

                            {!(
                              rule.amount_type === "cod" && rule.amount == 0
                            ) && (
                              <div
                                style={{
                                  fontSize: "12px",
                                  color: "#6b7280",
                                  marginTop: "4px",
                                }}
                              >
                                {settings?.partialPaymentFlowVersion === 2
                                  ? getDescBundle(rule)
                                  : getDesc(rule)}
                              </div>
                            )}

                            <div
                              style={{
                                display: "flex",
                                gap: "8px",
                                marginTop: "8px",
                                flexWrap: "wrap",
                              }}
                            >
                              {rule.amount_type === "cod" &&
                                rule.amount > 0 && (
                                  <CodFeeBadge>
                                    {formatCurrency(
                                      parseFloat(rule.amount),
                                      currencyCode
                                    )}{" "}
                                    COD fee added
                                  </CodFeeBadge>
                                )}

                              {ruleHasDiscount && (
                                <DiscountTagBadge>
                                  Get{" "}
                                  {rule.discount_type === "percentage"
                                    ? `${convertFloatToInt(
                                        rule.discount_value
                                      )}%`
                                    : formatCurrency(
                                        parseFloat(rule.discount_value),
                                        currencyCode
                                      )}
                                  &nbsp;Off
                                </DiscountTagBadge>
                              )}
                            </div>
                          </div>

                          {/* Price display */}
                          <div
                            style={{ textAlign: "right", whiteSpace: "nowrap" }}
                          >
                            <div style={{ fontWeight: 600, fontSize: "16px" }}>
                              {settings?.partialPaymentFlowVersion === 2
                                ? getPriceBundle(rule)
                                : getPrice(rule)}
                            </div>
                            {settings?.preV2PartialTaxText && (
                              <div
                                style={{
                                  fontSize: "12px",
                                  color: "#6b7280",
                                  marginTop: "0px",
                                }}
                              >
                                {settings.preV2PartialTaxText}
                              </div>
                            )}
                          </div>

                          {/* Custom checkmark */}
                          <CheckmarkIcon
                            isSelected={selectedRule === rule.id}
                          />
                        </PaymentOptionContent>
                      </PaymentOptionLabel>
                    );
                  })}
                </PaymentOptionsContainer>
              </div>
            )
          )}

          <>
            <br />
            <StickyFooter>
              {error && <ErrorMessage>{error}</ErrorMessage>}
              <CodkingButton
                onClick={handleSubmit}
                disabled={!isCartReady}
                loading={isPartialLoading || isCreatingCarts}
                fullWidth
              >
                Proceed to Payment
              </CodkingButton>
            </StickyFooter>
          </>
        </BlockInteractionWrapper>
      )}
    </MobilePartialPaymentComponentContainer>
  );
};

export default MobilePartialPaymentComponent;
