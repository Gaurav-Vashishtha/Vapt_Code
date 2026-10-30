import React from "react";
import styled from "styled-components";
import { BlockStack, Text } from "@shopify/polaris";
import { t } from "../i18n";

const Row = styled.div`
  display: grid;
  grid-template-columns: minmax(110px, 180px) 1fr minmax(70px, auto);
  gap: 12px;
  align-items: center;

  @media (max-width: 480px) {
    grid-template-columns: 1fr auto;

    > div[data-track] {
      grid-column: 1 / -1;
      order: 3;
    }
  }
`;

const Track = styled.div`
  height: 22px;
  border-radius: 6px;
  background: var(--p-color-bg-surface-secondary, #f1f1f1);
  overflow: hidden;

  > span {
    display: block;
    height: 100%;
    min-width: 2px;
    border-radius: 6px;
    background: #007ace;
    transition: width 200ms ease;
  }
`;

export const funnelStepLabel = (step) => {
  switch (step) {
    case "button_views":
      return t("analytics.button_views", "Button views");
    case "form_opens":
      return t("analytics.form_opens", "Form opens");
    case "first_inputs":
      return t("analytics.first_inputs", "Started typing");
    case "shipping_selected":
      return t("analytics.shipping_selected", "Shipping selected");
    case "submit_attempts":
      return t("analytics.submit_attempts", "Submit attempts");
    case "orders":
      return t("analytics.orders", "Orders");
    default:
      return step;
  }
};

/** Funnel from button view to order (ANL-2): one bar per step, with the share of the first step. */
const FunnelChart = ({ funnel }) => {
  const steps = Array.isArray(funnel) ? funnel : [];
  const top = steps.reduce((max, step) => Math.max(max, Number(step.count) || 0), 0);
  if (steps.length === 0 || top === 0) {
    return (
      <Text as="p" tone="subdued">
        {t("analytics.empty", "No form activity in this period yet.")}
      </Text>
    );
  }
  const first = Number(steps[0].count) || top;
  return (
    <BlockStack gap="200">
      {steps.map((step, index) => {
        const count = Number(step.count) || 0;
        const previous = index > 0 ? Number(steps[index - 1].count) || 0 : 0;
        const share = first > 0 ? (count / first) * 100 : 0;
        const stepRate = index > 0 && previous > 0 ? (count / previous) * 100 : null;
        return (
          <Row key={step.step}>
            <Text as="span" variant="bodyMd">
              {funnelStepLabel(step.step)}
            </Text>
            <Track data-track>
              <span style={{ width: `${Math.max(0, Math.min(100, (count / top) * 100))}%` }} />
            </Track>
            <Text as="span" variant="bodyMd" alignment="end">
              <strong>{count.toLocaleString()}</strong>
              <Text as="span" variant="bodySm" tone="subdued">
                {" "}
                {stepRate !== null ? `${stepRate.toFixed(0)}%` : `${share.toFixed(0)}%`}
              </Text>
            </Text>
          </Row>
        );
      })}
      <Text as="p" variant="bodySm" tone="subdued">
        {t("analytics.funnel_note", "The percentage next to each step is the share of buyers who came from the step before.")}
      </Text>
    </BlockStack>
  );
};

export default FunnelChart;
