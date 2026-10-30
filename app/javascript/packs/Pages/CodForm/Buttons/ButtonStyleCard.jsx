import React from "react";
import { BlockStack, Checkbox, InlineGrid, RangeSlider, Select } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import ColorField from "../components/ColorField";
import LocalizedTextField from "../components/LocalizedTextField";
import { contrastRatio } from "../utils";
import { t } from "../i18n";

/** Label, subtitle and styling of the COD button (BTN-6). */
const ButtonStyleCard = ({ button, onChange }) => {
  const style = button.style || {};
  const set = (key) => (value) => onChange(["button", "style", key], value);
  const ratio = contrastRatio(style.color, style.bg);

  return (
    <SectionCard
      title={t("buttons.style_title", "COD button")}
      description={t("buttons.style_help", "The text and look of the Buy with COD button.")}
    >
      <BlockStack gap="400">
        <LocalizedTextField
          label={t("buttons.label", "Button label")}
          value={button.labels}
          onChange={(value) => onChange(["button", "labels"], value)}
          helpText={t("buttons.total_variable_help", "Use {total} to show the price, for example \"Buy with COD — {total}\".")}
          maxLength={60}
        />
        <LocalizedTextField
          label={t("buttons.subtitle", "Subtitle (optional)")}
          value={button.subtitles}
          onChange={(value) => onChange(["button", "subtitles"], value)}
          maxLength={80}
        />
        <InlineGrid columns={{ xs: 1, sm: 3 }} gap="400">
          <ColorField
            label={t("buttons.bg", "Background")}
            value={style.bg}
            onChange={set("bg")}
          />
          <ColorField
            label={t("buttons.color", "Text")}
            value={style.color}
            onChange={set("color")}
            helpText={ratio !== null && ratio < 3 ? t("buttons.contrast_warning", "Low contrast: the label may be hard to read.") : undefined}
          />
          <ColorField label={t("buttons.border", "Border")} value={style.border_color} onChange={set("border_color")} />
        </InlineGrid>
        <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
          <RangeSlider
            label={t("buttons.border_width", "Border width")}
            min={0}
            max={6}
            value={Number(style.border_width) || 0}
            onChange={set("border_width")}
            output
            suffix={`${Number(style.border_width) || 0}px`}
          />
          <RangeSlider
            label={t("buttons.radius", "Corner radius")}
            min={0}
            max={30}
            value={Number(style.radius) || 0}
            onChange={set("radius")}
            output
            suffix={`${Number(style.radius) || 0}px`}
          />
          <RangeSlider
            label={t("buttons.font_size", "Text size")}
            min={12}
            max={22}
            value={Number(style.font_size) || 16}
            onChange={set("font_size")}
            output
            suffix={`${Number(style.font_size) || 16}px`}
          />
          <RangeSlider
            label={t("buttons.height", "Height")}
            min={36}
            max={64}
            value={Number(style.height) || 48}
            onChange={set("height")}
            output
            suffix={`${Number(style.height) || 48}px`}
          />
        </InlineGrid>
        <InlineGrid columns={{ xs: 1, sm: 3 }} gap="400">
          <Select
            label={t("buttons.shadow", "Shadow")}
            options={[
              { label: t("buttons.shadow_none", "None"), value: "none" },
              { label: t("buttons.shadow_sm", "Small"), value: "sm" },
              { label: t("buttons.shadow_md", "Medium"), value: "md" },
              { label: t("buttons.shadow_lg", "Large"), value: "lg" },
            ]}
            value={style.shadow || "none"}
            onChange={set("shadow")}
          />
          <Select
            label={t("buttons.icon", "Icon")}
            options={[
              { label: t("buttons.icon_none", "No icon"), value: "none" },
              { label: t("buttons.icon_cash", "Cash"), value: "cash" },
              { label: t("buttons.icon_truck", "Truck"), value: "truck" },
              { label: t("buttons.icon_cart", "Cart"), value: "cart" },
              { label: t("buttons.icon_bolt", "Bolt"), value: "bolt" },
            ]}
            value={style.icon || "none"}
            onChange={set("icon")}
          />
          <Select
            label={t("buttons.animation", "Animation")}
            options={[
              { label: t("buttons.animation_none", "None"), value: "none" },
              { label: t("buttons.animation_pulse", "Pulse"), value: "pulse" },
              { label: t("buttons.animation_shake", "Shake"), value: "shake" },
            ]}
            value={style.animation || "none"}
            onChange={set("animation")}
          />
        </InlineGrid>
        <InlineGrid columns={{ xs: 1, sm: 2 }} gap="200">
          <Checkbox label={t("buttons.bold", "Bold label")} checked={style.bold !== false} onChange={set("bold")} />
          <Checkbox label={t("buttons.full_width", "Full width")} checked={style.full_width !== false} onChange={set("full_width")} />
        </InlineGrid>
      </BlockStack>
    </SectionCard>
  );
};

export default ButtonStyleCard;
