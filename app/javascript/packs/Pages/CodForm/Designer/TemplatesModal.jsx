import React from "react";
import styled from "styled-components";
import { Modal, BlockStack, InlineGrid, Text, Button } from "@shopify/polaris";
import Gate from "../components/Gate";
import { FEATURES } from "../constants";
import { t } from "../i18n";

const Swatches = styled.div`
  display: flex;
  height: 56px;
  border-radius: ${(p) => Math.min(Number(p.$radius) || 0, 16)}px;
  overflow: hidden;
  border: 1px solid var(--p-color-border, #e3e3e3);

  span {
    flex: 1;
  }
`;

const templateName = (template) => {
  switch (template.key) {
    case "classic":
      return t("designer.template_classic", "Classic");
    case "minimal":
      return t("designer.template_minimal", "Minimal");
    case "bold":
      return t("designer.template_bold", "Bold");
    case "compact":
      return t("designer.template_compact", "Compact");
    default:
      return template.name || template.key;
  }
};

/** Design templates (FRM-21). Applying one replaces the design and the block order only. */
const TemplatesModal = ({ open, templates, onClose, onApply }) => (
  <Modal
    open={open}
    onClose={onClose}
    title={t("designer.templates", "Templates")}
    secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: onClose }]}
  >
    <Modal.Section>
      <Gate feature={FEATURES.TEMPLATES} compact title={t("designer.templates", "Templates")}>
        <BlockStack gap="400">
          <Text as="p" tone="subdued">
            {t("designer.templates_help", "A template changes colours, shape and the order of blocks. Your fields and texts stay as they are. Nothing goes live until you publish.")}
          </Text>
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            {(templates || []).map((template) => {
              const design = template.design || {};
              return (
                <BlockStack key={template.key} gap="200">
                  <Swatches $radius={design.radius} aria-hidden="true">
                    <span style={{ background: design.background }} />
                    <span style={{ background: design.surface }} />
                    <span style={{ background: design.primary }} />
                    <span style={{ background: design.text }} />
                  </Swatches>
                  <Text as="h4" variant="headingSm">
                    {templateName(template)}
                  </Text>
                  <Button onClick={() => onApply(template)}>{t("designer.template_apply", "Use this template")}</Button>
                </BlockStack>
              );
            })}
          </InlineGrid>
        </BlockStack>
      </Gate>
    </Modal.Section>
  </Modal>
);

export default TemplatesModal;
