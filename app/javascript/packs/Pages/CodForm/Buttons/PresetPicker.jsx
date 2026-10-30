import React from "react";
import styled from "styled-components";
import { BlockStack, InlineGrid, InlineStack, Text, Badge } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import { useGate, UpgradeCard } from "../components/Gate";
import { FEATURES } from "../constants";
import { t } from "../i18n";

const Choice = styled.button`
  appearance: none;
  text-align: start;
  width: 100%;
  height: 100%;
  padding: 16px;
  border-radius: 12px;
  cursor: pointer;
  background: ${(p) => (p.$selected ? "var(--p-color-bg-surface-selected, #f1f1f1)" : "var(--p-color-bg-surface, #fff)")};
  border: 2px solid ${(p) => (p.$selected ? "var(--p-color-border-emphasis, #005bd3)" : "var(--p-color-border, #e3e3e3)")};
  font: inherit;
  color: inherit;

  &:disabled {
    cursor: not-allowed;
    opacity: 0.6;
  }

  &:focus-visible {
    outline: 2px solid var(--p-color-border-focus, #005bd3);
    outline-offset: 2px;
  }
`;

const Mini = styled.div`
  display: flex;
  flex-direction: column;
  gap: 4px;
  margin-bottom: 12px;

  span {
    height: 14px;
    border-radius: 4px;
    border: 1px solid #1a1a1a;
  }

  span[data-solid] {
    background: #1a1a1a;
  }

  span[data-cod] {
    background: #008060;
    border-color: #008060;
  }
`;

/** Preset cards in the order of spec §3: B (default), C, A. */
const PresetPicker = ({ preset, onChange }) => {
  const gateA = useGate(FEATURES.PRESET_A);
  const presets = [
    {
      key: "B",
      title: t("buttons.preset_b", "COD button + Buy now"),
      help: t("buttons.preset_b_help", "Adds a Buy with COD button. Your theme's Buy now button stays as it is and goes to Shopify checkout."),
      badge: t("buttons.preset_default_badge", "Default"),
      bars: ["atc", "cod", "solid"],
    },
    {
      key: "C",
      title: t("buttons.preset_c", "COD button + renamed Buy now"),
      help: t("buttons.preset_c_help", "Adds a Buy with COD button and relabels your theme's Buy now button, for example \"Buy with prepaid\", to push online payment."),
      bars: ["atc", "cod", "solid"],
    },
    {
      key: "A",
      title: t("buttons.preset_a", "Single button"),
      help: t("buttons.preset_a_help", "No extra button. Your theme's Buy now button opens the form, and the buyer picks COD or Pay online inside."),
      bars: ["atc", "cod"],
      locked: !gateA.allowed,
    },
  ];

  return (
    <SectionCard
      title={t("buttons.preset_title", "Button preset")}
      description={t("buttons.preset_help", "Choose how the COD button sits next to your theme's own buttons. You can change this at any time.")}
    >
      <BlockStack gap="300">
        <InlineGrid columns={{ xs: 1, md: 3 }} gap="300">
          {presets.map((item) => (
            <Choice
              key={item.key}
              type="button"
              $selected={preset === item.key}
              aria-pressed={preset === item.key}
              disabled={item.locked}
              onClick={() => onChange(item.key)}
            >
              <Mini aria-hidden="true">
                {item.bars.map((bar, index) => (
                  <span key={index} data-solid={bar === "solid" ? "" : undefined} data-cod={bar === "cod" ? "" : undefined} />
                ))}
              </Mini>
              <BlockStack gap="100">
                <InlineStack gap="200" blockAlign="center">
                  <Text as="span" variant="headingSm">
                    {item.title}
                  </Text>
                  {item.badge && <Badge>{item.badge}</Badge>}
                </InlineStack>
                <Text as="span" variant="bodySm" tone="subdued">
                  {item.help}
                </Text>
              </BlockStack>
            </Choice>
          ))}
        </InlineGrid>
        {!gateA.allowed && (
          <UpgradeCard compact minTier={gateA.minTier} title={t("buttons.preset_a", "Single button")} />
        )}
      </BlockStack>
    </SectionCard>
  );
};

export default PresetPicker;
