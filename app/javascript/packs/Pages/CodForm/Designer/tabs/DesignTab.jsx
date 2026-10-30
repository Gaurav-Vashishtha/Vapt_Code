import React from "react";
import { Banner, BlockStack, Button, Card, Checkbox, InlineGrid, InlineStack, RangeSlider, Select, Text, TextField } from "@shopify/polaris";
import ColorField from "../../components/ColorField";
import { contrastRatio } from "../../utils";
import { FORM_THEMES } from "../../defaults";
import { t } from "../../i18n";
import LogoField from "../../components/LogoField";

/** Design tokens of the form (FRM-8) and the templates entry point (FRM-21). */
const DesignTab = ({ config, setConfig, onOpenTemplates }) => {
  const design = config.design || {};
  const header = design.header || {};
  const set = (key) => (value) => setConfig((current) => ({ ...current, design: { ...(current.design || {}), [key]: value } }));
  const setHeader = (key) => (value) =>
    setConfig((current) => ({
      ...current,
      design: { ...(current.design || {}), header: { ...((current.design || {}).header || {}), [key]: value } },
    }));

  const theme = design.theme === "express" ? "express" : "classic";
  const setTheme = (value) => {
    if (value === theme) return;
    setConfig((current) => ({ ...current, design: { ...(current.design || {}), ...FORM_THEMES[value], theme: value } }));
  };
  const themes = [
    {
      value: "classic",
      label: t("designer.theme_classic", "Classic"),
      help: t("designer.theme_classic_help", "Large labels beside the fields and a big order button."),
    },
    {
      value: "express",
      label: t("designer.theme_express", "Express"),
      help: t("designer.theme_express_help", "The look of the COD King checkout: white cards, small labels above the fields and a compact button."),
    },
  ];

  const buttonContrast = contrastRatio(design.on_primary, design.primary);
  const textContrast = contrastRatio(design.text, design.background);
  const lowContrast = (buttonContrast !== null && buttonContrast < 4.5) || (textContrast !== null && textContrast < 4.5);

  return (
    <BlockStack gap="400">
      <Card>
        <BlockStack gap="300">
          <Text as="h3" variant="headingSm">
            {t("designer.theme_title", "Theme")}
          </Text>
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="300">
            {themes.map((item) => (
              <div
                key={item.value}
                role="radio"
                aria-checked={theme === item.value}
                tabIndex={0}
                onClick={() => setTheme(item.value)}
                onKeyDown={(event) => (event.key === "Enter" || event.key === " ") && (event.preventDefault(), setTheme(item.value))}
                style={{
                  cursor: "pointer",
                  padding: 12,
                  borderRadius: 8,
                  border: theme === item.value ? "2px solid #1a1a1a" : "1px solid #d9d9de",
                  margin: theme === item.value ? 0 : 1,
                  background: "#fff",
                }}
              >
                <BlockStack gap="100">
                  <Text as="span" variant="bodyMd" fontWeight="semibold">
                    {item.label}
                  </Text>
                  <Text as="span" variant="bodySm" tone="subdued">
                    {item.help}
                  </Text>
                </BlockStack>
              </div>
            ))}
          </InlineGrid>
          <Text as="p" variant="bodySm" tone="subdued">
            {t("designer.theme_note", "Choosing a theme sets its colours and corner radius. You can change them below afterwards.")}
          </Text>
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="400">
          <InlineStack align="space-between" blockAlign="center">
            <Text as="h3" variant="headingSm">
              {t("designer.design_colors", "Colours")}
            </Text>
            <Button onClick={onOpenTemplates}>{t("designer.templates", "Templates")}</Button>
          </InlineStack>
          {lowContrast && (
            <Banner tone="warning">
              <p>{t("designer.contrast_warning", "Some of these colours are hard to read together. Aim for stronger contrast between text and its background.")}</p>
            </Banner>
          )}
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            <ColorField label={t("designer.design_primary", "Primary (button)")} value={design.primary} onChange={set("primary")} />
            <ColorField label={t("designer.design_on_primary", "Text on the button")} value={design.on_primary} onChange={set("on_primary")} />
            <ColorField label={t("designer.design_text", "Text")} value={design.text} onChange={set("text")} />
            <ColorField label={t("designer.design_muted", "Secondary text")} value={design.muted} onChange={set("muted")} />
            <ColorField label={t("designer.design_background", "Background")} value={design.background} onChange={set("background")} />
            <ColorField label={t("designer.design_surface", "Panels")} value={design.surface} onChange={set("surface")} />
            <ColorField label={t("designer.design_border", "Borders")} value={design.border} onChange={set("border")} />
            <ColorField label={t("designer.design_error", "Errors")} value={design.error} onChange={set("error")} />
          </InlineGrid>
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="400">
          <Text as="h3" variant="headingSm">
            {t("designer.design_shape", "Shape and spacing")}
          </Text>
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            <RangeSlider
              label={t("designer.design_radius", "Form corner radius")}
              min={0}
              max={28}
              value={Number(design.radius) || 0}
              onChange={set("radius")}
              output
              suffix={`${Number(design.radius) || 0}px`}
            />
            <RangeSlider
              label={t("designer.design_field_radius", "Field corner radius")}
              min={0}
              max={20}
              value={Number(design.field_radius) || 0}
              onChange={set("field_radius")}
              output
              suffix={`${Number(design.field_radius) || 0}px`}
            />
          </InlineGrid>
          <Select
            label={t("designer.design_density", "Spacing")}
            options={[
              { label: t("designer.density_comfortable", "Comfortable"), value: "comfortable" },
              { label: t("designer.density_compact", "Compact"), value: "compact" },
            ]}
            value={design.density || "comfortable"}
            onChange={set("density")}
          />
          <Text as="p" variant="bodySm" tone="subdued">
            {theme === "express" ? t("designer.font_note_express", "The Express theme uses its own font (Metropolis).") : t("designer.font_note", "The font is inherited from your theme.")}
          </Text>
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="400">
          <Text as="h3" variant="headingSm">
            {t("designer.design_header", "Header and behaviour")}
          </Text>
          <Checkbox
            label={t("designer.design_header_title", "Show the title")}
            checked={header.show_title !== false}
            onChange={setHeader("show_title")}
          />
          <LogoField value={header.logo_url || ""} onChange={setHeader("logo_url")} />
          <Checkbox
            label={t("designer.sticky_submit", "Keep the submit button visible while scrolling")}
            checked={design.sticky_submit !== false}
            onChange={set("sticky_submit")}
          />
          <Checkbox
            label={t("designer.hide_single_shipping", "Hide the shipping selector when only one rate applies")}
            checked={design.hide_shipping_selector_when_single !== false}
            onChange={set("hide_shipping_selector_when_single")}
          />
          <Checkbox
            label={t("designer.pay_online_enabled", "Offer \"Pay online instead\" to blocked buyers")}
            checked={config.pay_online ? config.pay_online.enabled !== false : true}
            onChange={(value) => setConfig((current) => ({ ...current, pay_online: { ...(current.pay_online || {}), enabled: value } }))}
          />
        </BlockStack>
      </Card>
    </BlockStack>
  );
};

export default DesignTab;
