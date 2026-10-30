import { Card, Text } from "@shopify/polaris";
import React, { useContext } from "react";
import I18n from "../i18n-lang";
import { StoreContext } from "../Context/Store";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";

const WizardSteps = ({ currentStep = 1, onStepClick }) => {
  const { setting, setSetting } = useContext(StoreContext);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);
  const steps = [
    {
      step: 1,
      label: I18n.t("quick_current_step.select_integration"),
      description: I18n.t("quick_current_step.select_integration_description"),
    },
    {
      step: 2,
      label: I18n.t("quick_current_step.activate_configure"),
      description: I18n.t("quick_current_step.activate_configure_description"),
    },
    {
      step: 3,
      label: I18n.t("quick_current_step.test_billing"),
      description: I18n.t("quick_current_step.test_billing_description"),
    },
  ];

  const getStepStatus = (stepNumber) => {
    if (currentStep > stepNumber) return "completed";
    if (currentStep === stepNumber) return "current";
    return "pending";
  };

  const getStepStyles = (status) => {
    const baseStyles = {
      width: "28px",
      height: "28px",
      borderRadius: "50%",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: "12px",
      fontWeight: "600",
      transition: "all 0.2s ease-in-out",
      border: "2px solid",
    };

    switch (status) {
      case "completed":
        return {
          ...baseStyles,
          backgroundColor: "#008060",
          borderColor: "#008060",
          color: "#ffffff",
        };
      case "current":
        return {
          ...baseStyles,
          backgroundColor: "#ffffff",
          borderColor: "#008060",
          color: "#008060",
        };
      default:
        return {
          ...baseStyles,
          backgroundColor: "#f6f6f7",
          borderColor: "#c9cccf",
          color: "#6d7175",
        };
    }
  };

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        position: "relative",
        padding: "12px 16px",
        borderBottom: "1px solid #E1E3E5",
        backgroundColor: "#FAFBFC",
      }}
    >
      {steps.map((step, index) => {
        const status = getStepStatus(step.step);
        const stepStyles = getStepStyles(status);
        const isClickable =
          onStepClick && (status === "completed" || status === "current");

        return (
          <div
            key={step.step}
            style={{
              flex: 1,
              display: "flex",
              flexDirection: "row",
              alignItems: "center",
              position: "relative",
              cursor: isClickable ? "pointer" : "default",
              minWidth: "0",
              padding: "0 4px",
            }}
            onClick={
              isClickable
                ? () => {
                    journeyTracker.trackButtonClick("step_click", {
                      step: step.step,
                      feature: "step-navigation",
                      clickedStep: step.step,
                      currentStep: currentStep,
                    });
                    onStepClick(step.step);
                  }
                : undefined
            }
          >
            {/* Step circle */}
            <div
              style={{
                ...stepStyles,
                position: "relative",
                zIndex: 2,
                marginRight: "12px",
                flexShrink: 0,
              }}
            >
              {status === "completed" ? (
                <svg
                  width="14"
                  height="14"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                >
                  <path
                    fillRule="evenodd"
                    d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                    clipRule="evenodd"
                  />
                </svg>
              ) : (
                step.step
              )}
            </div>

            {/* Step content */}
            <div
              style={{
                flex: 1,
              }}
            >
              <div
                style={{
                  fontSize: "13px",
                  fontWeight: status === "current" ? "600" : "500",
                  color: status === "pending" ? "#6d7175" : "#202223",
                  lineHeight: "16px",
                  fontFamily:
                    "-apple-system, BlinkMacSystemFont, San Francisco, Segoe UI, Roboto, Helvetica Neue, sans-serif",
                  marginBottom: "1px",
                }}
              >
                {step.label}
              </div>
              <div
                style={{
                  fontSize: "11px",
                  color: "#6d7175",
                  lineHeight: "13px",
                  fontFamily:
                    "-apple-system, BlinkMacSystemFont, San Francisco, Segoe UI, Roboto, Helvetica Neue, sans-serif",
                }}
              >
                {step.description}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
};

const QuickCurrentStep = ({ currentStep }) => {
  return (
    <>
      <WizardSteps currentStep={currentStep} />
    </>
  );
};

export default QuickCurrentStep;
