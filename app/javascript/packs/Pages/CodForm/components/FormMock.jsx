import React, { useEffect } from "react";
import styled, { css } from "styled-components";
import { RTL_LOCALES } from "../constants";
import { formatMoney } from "../money";
import { resolveText } from "../Designer/texts";

/**
 * A static React rendering of the buyer form from a draft config (C.2).
 * It is a mock for the designer preview: fixture cart, no network, no
 * storefront code. Block order, enabled fields, widths, labels, placeholders
 * and the design tokens all come from the config being edited.
 */

const FIXTURE = {
  title: "Sample product",
  variant: "Default",
  price_cents: 249900,
  compare_at_cents: 329900,
  shipping: [
    { id: 1, name: "Standard delivery", description: "2–4 business days", price_cents: 14900 },
    { id: 2, name: "Express delivery", description: "Next business day", price_cents: 29900 },
  ],
  bump: { title: "Add express handling", description: "Ships tomorrow", price_cents: 4900 },
  tiers: [
    { label: "1 pack", quantity: 1, percent: 0, selected: false },
    { label: "2 packs", quantity: 2, percent: 10, selected: true, badge: "Most popular" },
    { label: "3 packs", quantity: 3, percent: 15, selected: false, badge: "Best value" },
  ],
  threshold_cents: 500000,
};

const Sheet = styled.div`
  --cf-primary: ${(p) => p.$d.primary};
  --cf-on-primary: ${(p) => p.$d.on_primary};
  --cf-text: ${(p) => p.$d.text};
  --cf-muted: ${(p) => p.$d.muted};
  --cf-bg: ${(p) => p.$d.background};
  --cf-surface: ${(p) => p.$d.surface};
  --cf-border: ${(p) => p.$d.border};
  --cf-error: ${(p) => p.$d.error};
  --cf-radius: ${(p) => Number(p.$d.radius) || 0}px;
  --cf-field-radius: ${(p) => Number(p.$d.field_radius) || 0}px;
  --cf-gap: ${(p) => (p.$d.density === "compact" ? "8px" : "12px")};
  --cf-pad: ${(p) => (p.$d.density === "compact" ? "12px" : "16px")};

  box-sizing: border-box;
  width: 100%;
  background: var(--cf-bg);
  color: var(--cf-text);
  border-radius: ${(p) => (p.$mobile ? "var(--cf-radius) var(--cf-radius) 0 0" : "var(--cf-radius)")};
  font-size: 14px;
  line-height: 1.4;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  text-align: start;

  * {
    box-sizing: border-box;
  }
`;

const Header = styled.div`
  display: flex;
  align-items: center;
  gap: 10px;
  padding: var(--cf-pad);
  border-bottom: 1px solid var(--cf-border);

  img {
    height: 28px;
    max-width: 120px;
    object-fit: contain;
  }

  strong {
    flex: 1;
    font-size: 16px;
  }

  span[data-close] {
    margin-inline-start: auto;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    background: var(--cf-surface);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    color: var(--cf-muted);
  }
`;

const Body = styled.div`
  padding: var(--cf-pad);
  display: flex;
  flex-direction: column;
  gap: calc(var(--cf-gap) + 4px);
`;

const SectionTitle = styled.div`
  font-weight: 600;
  margin-bottom: 6px;
`;

const Surface = styled.div`
  background: var(--cf-surface);
  border: 1px solid var(--cf-border);
  border-radius: var(--cf-field-radius);
  padding: 10px 12px;
`;

const Row = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
`;

const Muted = styled.span`
  color: var(--cf-muted);
  font-size: 12px;
`;

const Thumb = styled.div`
  flex: 0 0 auto;
  width: 48px;
  height: 48px;
  border-radius: var(--cf-field-radius);
  background: linear-gradient(135deg, var(--cf-border), var(--cf-surface));
  border: 1px solid var(--cf-border);
`;

const FieldsGrid = styled.div`
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--cf-gap);
`;

const FieldCell = styled.div`
  grid-column: ${(p) => (p.$full ? "1 / -1" : "auto")};
  min-width: 0;

  label {
    display: block;
    font-size: 12px;
    margin-bottom: 4px;
    color: var(--cf-text);
  }

  label em {
    color: var(--cf-error);
    font-style: normal;
  }
`;

const Input = styled.div`
  min-height: ${(p) => (p.$tall ? "64px" : "40px")};
  border: 1px solid var(--cf-border);
  border-radius: var(--cf-field-radius);
  background: var(--cf-bg);
  padding: 9px 12px;
  color: var(--cf-muted);
  display: flex;
  align-items: ${(p) => (p.$tall ? "flex-start" : "center")};
  justify-content: space-between;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
`;

const Check = styled.div`
  display: flex;
  align-items: flex-start;
  gap: 8px;

  i {
    flex: 0 0 auto;
    width: 16px;
    height: 16px;
    margin-top: 2px;
    border: 1px solid var(--cf-border);
    border-radius: ${(p) => (p.$round ? "50%" : "4px")};
    background: ${(p) => (p.$on ? "var(--cf-primary)" : "var(--cf-bg)")};
  }
`;

const Option = styled(Surface).attrs((p) => ({ "data-on": p.$on ? "1" : undefined }))`
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  border-color: ${(p) => (p.$on ? "var(--cf-primary)" : "var(--cf-border)")};
  box-shadow: ${(p) => (p.$on ? "inset 0 0 0 1px var(--cf-primary)" : "none")};
`;

const Submit = styled.div`
  background: var(--cf-primary);
  color: var(--cf-on-primary);
  border-radius: var(--cf-field-radius);
  padding: 14px 16px;
  text-align: center;
  font-weight: 700;
  font-size: 15px;
`;

const Footer = styled.div`
  padding: var(--cf-pad);
  border-top: ${(p) => (p.$sticky ? "1px solid var(--cf-border)" : "0")};
  background: var(--cf-bg);
  display: flex;
  flex-direction: column;
  gap: 8px;
  text-align: center;
`;

const Badge = styled.span`
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border-radius: 999px;
  background: var(--cf-surface);
  border: 1px solid var(--cf-border);
  font-size: 12px;
`;

const Bar = styled.div`
  height: 6px;
  border-radius: 999px;
  background: var(--cf-border);
  overflow: hidden;

  &::after {
    content: "";
    display: block;
    width: 62%;
    height: 100%;
    background: var(--cf-primary);
  }
`;

/* Mirrors of the storefront's checkout-style summary, tier cards and threshold card
   (core/blocks/OrderSummary.jsx, chunks/qty-offer.jsx, chunks/threshold.jsx). */
const SummaryCard = styled.div`
  background: var(--cf-surface);
  border: 1px solid var(--cf-border);
  border-radius: var(--cf-radius, 8px);
  overflow: hidden;
`;

const SummaryHead = styled.div`
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px;
  b { font-weight: 600; }
  s { color: var(--cf-muted); font-size: 12px; }
`;

const SaveStrip = styled.div`
  padding: 6px 12px;
  text-align: center;
  font-size: 12px;
  font-weight: 600;
  color: #238017;
  background: #e3f6e8;
`;

const Tiers = styled.div`
  display: grid;
  gap: 10px;
  padding-top: 9px;
`;

const Tier = styled.div`
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 3px;
  text-align: center;
  padding: ${(p) => (p.$badge ? "17px" : "12px")} 6px 9px;
  background: ${(p) => (p.$on ? "color-mix(in srgb, var(--cf-primary) 6%, var(--cf-bg))" : "var(--cf-bg)")};
  border: 1.5px solid ${(p) => (p.$on ? "var(--cf-primary)" : "var(--cf-border)")};
  box-shadow: ${(p) => (p.$on ? "inset 0 0 0 1px var(--cf-primary), 0 4px 14px rgba(0,0,0,.08)" : "none")};
  border-radius: var(--cf-field-radius);
  &::before {
    content: "";
    position: absolute;
    top: 8px;
    inset-inline-start: 8px;
    width: 14px;
    height: 14px;
    box-sizing: border-box;
    border-radius: 50%;
    border: ${(p) => (p.$on ? "4px solid var(--cf-primary)" : "2px solid var(--cf-border)")};
    background: var(--cf-bg);
  }
`;

const TierBadge = styled.span`
  position: absolute;
  top: -9px;
  left: 50%;
  transform: translateX(-50%);
  white-space: nowrap;
  padding: 2px 7px;
  border-radius: 999px;
  background: var(--cf-primary);
  color: var(--cf-on-primary);
  font-size: 10px;
  font-weight: 700;
`;

const SaveChip = styled.span`
  margin-top: 3px;
  padding: 2px 6px;
  border-radius: 999px;
  background: #e3f6e8;
  color: #238017;
  font-size: 10px;
  font-weight: 700;
`;

const ThresholdCard = styled(Surface)`
  display: flex;
  flex-direction: column;
  gap: 8px;
`;

const fill = (text, vars) =>
  String(text || "").replace(/\{(\w+)\}/g, (match, name) => (vars[name] !== undefined ? vars[name] : match));

const stripTags = (html) => String(html || "").replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();

/* design.theme === "express": the look of the COD King checkout widget. Same blocks, restyled. */
const EXPRESS_FONT = "https://cdn.jsdelivr.net/npm/@fontsource/metropolis@5.3.0/";
const Skin = styled(Sheet)`
  /* Classic (the default theme): labels beside the fields, one field per row, bold headings. */
  ${(p) =>
    p.$d.theme !== "express" &&
    css`
      ${Header} strong {
        font-size: 17px;
        font-weight: 800;
        letter-spacing: 0.04em;
        text-transform: uppercase;
      }

      ${SectionTitle} {
        font-size: 18px;
        font-weight: 800;
        text-align: center;
        margin-bottom: 14px;
      }

      ${FieldsGrid} {
        grid-template-columns: 1fr;
        gap: 18px;
      }

      ${FieldCell} {
        grid-column: 1 / -1;
        display: grid;
        grid-template-columns: minmax(84px, 26%) minmax(0, 1fr);
        column-gap: 12px;
        align-items: center;
      }

      ${FieldCell} label {
        margin-bottom: 0;
        font-size: 15px;
        font-weight: 700;
        line-height: 1.2;
      }

      ${FieldCell} > ${Check} {
        grid-column: 2;
      }

      ${FieldCell} > ${Check}:only-child {
        grid-column: 1 / -1;
      }

      ${Input} {
        min-height: 46px;
        font-size: 15px;
      }

      ${Submit} {
        border-radius: var(--cf-radius);
        font-size: 16px;
      }
    `}
  ${(p) =>
    p.$d.theme === "express" &&
    css`
      --x-blue: #3173e3;
      --x-hairline: #eceff4;
      --x-field: rgba(49, 115, 227, 0.2);
      background: #f9fafd;
      color: #2f2f2f;
      font-family: Metropolis, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      border-radius: ${p.$mobile ? "0" : "16px"};

      ${Header} {
        position: relative;
        justify-content: center;
        min-height: 52px;
        padding: 0 48px;
        background: #fff;
        border-bottom: 1px solid var(--x-hairline);

        strong {
          flex: 0 1 auto;
          font-size: 15px;
          font-weight: 600;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        span[data-close] {
          position: absolute;
          inset-inline-start: 8px;
          width: 34px;
          height: 34px;
          border-radius: 8px;
          background: none;
          color: #2f2f2f;
        }

        img + strong {
          display: none;
        }
      }

      &[dir="rtl"] span[data-close] svg {
        transform: scaleX(-1);
      }

      ${Body} {
        padding: 14px;
        gap: 16px;
      }

      ${Body} > * {
        background: #fff;
        border: 0;
        border-radius: 12px;
        padding: 14px;
        box-shadow: 4px 4px 11px #d0dbf726, -2px -2px 10px #d0dbf726;
      }

      ${Body} > ${SummaryCard} {
        padding: 0;
      }

      ${SummaryHead} {
        padding: 14px;
        b { font-size: 15px; }
        s { color: #8c8c8c; font-size: 13px; }
      }

      ${SaveStrip} {
        padding: 5px 20px;
        background: linear-gradient(90deg, #d8f4e1, #dcffe6);
      }

      ${SummaryHead} ${Muted}::before {
        content: "(";
      }

      ${SummaryHead} ${Muted}::after {
        content: ")";
      }

      ${Tiers}, ${Option} ${Check} {
        --cf-primary: var(--x-blue);
      }

      ${Tier} {
        border-width: 1px;
        border-radius: 12px;
      }

      ${TierBadge} {
        border-radius: 4px;
        background: #3c9726;
        color: #fff;
      }

      ${SectionTitle} {
        font-size: 16px;
        font-weight: 600;
        margin-bottom: 16px;
      }

      ${FieldsGrid} {
        gap: 18px 12px;
      }

      ${FieldCell} {
        position: relative;
      }

      ${FieldCell}:has(> ${Input}) > label {
        position: absolute;
        top: -8px;
        inset-inline-start: 10px;
        z-index: 1;
        max-width: calc(100% - 20px);
        margin: 0;
        padding: 0 4px;
        background: #fff;
        color: #6b7280;
        font-weight: 500;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      ${Input} {
        min-height: 47px;
        border-color: var(--x-field);
        border-radius: 6px;
        padding: 12px 14px;
        font-size: 15px;
        color: #b0b0b0;
        box-shadow: 0 3px 6px rgba(224, 224, 224, 0.3);
      }

      ${Option} {
        border: 0;
        border-bottom: 2px dashed var(--x-hairline);
        border-radius: 0;
        background: none;
        box-shadow: none;
        padding: 12px 4px;
        min-height: 60px;
      }

      ${Option}:last-child {
        border-bottom: 0;
      }

      /* Quantity tiers (side by side) keep their boxes. */
      ${Option}[style] {
        border: 1px solid var(--x-field);
        border-radius: 12px;
        padding: 10px;
        min-height: 0;
      }

      ${Option}[style][data-on] {
        border-color: var(--x-blue);
        background: #f5f9ff;
        box-shadow: 0 0 0 1px var(--x-blue);
      }

      ${Check} i {
        border-color: var(--x-field);
      }

      ${Footer} {
        padding: 12px 14px 10px;
        background: #fff;
        border-top: 1px solid var(--x-hairline);
        box-shadow: 0 -4px 16px rgba(16, 24, 40, 0.06);
      }

      ${Footer} [data-pay] {
        display: block;
        padding: 11px;
        border: 1px solid var(--x-blue);
        border-radius: 6px;
        color: var(--x-blue) !important;
        text-decoration: none !important;
        font-weight: 600;
      }

      ${Footer} ${Muted} {
        color: #4e596f;
        font-weight: 500;
      }

      ${Submit} {
        border-radius: 6px;
        padding: 14px 16px;
        font-size: 15px;
        font-weight: 600;
      }
    `}
`;

const FormMock = ({
  config,
  defaultsTexts,
  locale = "en",
  device = "mobile",
  view = "form",
  moneyFormat,
  currency,
  countriesCount = 1,
  shopCountry,
  hidePoweredBy = false,
}) => {
  const express = !!config && (config.design || {}).theme === "express";
  useEffect(() => {
    if (!express || document.getElementById("codkf-font")) return;
    [400, 500, 600, 700].forEach((weight, index) => {
      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = `${EXPRESS_FONT}${weight}.css`;
      if (index === 0) link.id = "codkf-font";
      document.head.appendChild(link);
    });
  }, [express]);
  if (!config) return null;
  const design = config.design || {};
  const header = design.header || {};
  const mobile = device === "mobile";
  const language = String(locale).split("-")[0];
  const rtl = RTL_LOCALES.includes(language);
  const tx = (key) => resolveText(config, defaultsTexts, locale, key);
  const money = (cents) => formatMoney(cents, moneyFormat, currency);

  const blocks = (config.blocks || []).filter((block) => block.enabled);
  const fields = config.fields || [];
  const subtotal = FIXTURE.price_cents;
  const shipping = FIXTURE.shipping[0].price_cents;
  const total = subtotal + shipping;
  const vars = {
    total: money(total),
    first_name: "Alex",
    last_name: "Kovács",
    order_name: "#1042",
    order_number: "1042",
    order_id: "5550001042",
    phone: "+36 30 123 4567",
    email: "alex@example.com",
    seconds: "30",
    remaining: money(50000),
    count: "2",
  };

  const visibleField = (field) => {
    if (!field.enabled) return false;
    if (field.key === "country" && countriesCount <= 1) return false;
    if (Array.isArray(field.only_countries) && field.only_countries.length > 0) {
      return !!shopCountry && field.only_countries.includes(shopCountry);
    }
    return true;
  };

  const renderField = (field) => {
    const label = tx(`label_${field.key}`) || field.key;
    const placeholder = tx(`placeholder_${field.key}`);
    const required = field.required === true || field.required === null;
    const full = mobile ? field.width !== "half" || ["consent", "checkbox", "radio", "textarea"].includes(field.type) : field.width !== "half";
    const labelNode = (
      <label>
        {label} {required && <em>*</em>}
      </label>
    );
    if (field.type === "consent" || field.type === "checkbox") {
      return (
        <FieldCell key={field.key} $full>
          <Check $on={!!field.default_checked}>
            <i />
            <span>
              {label} {required && <em style={{ color: "var(--cf-error)", fontStyle: "normal" }}>*</em>}
            </span>
          </Check>
        </FieldCell>
      );
    }
    if (field.type === "radio") {
      return (
        <FieldCell key={field.key} $full>
          {labelNode}
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            {(field.options || []).slice(0, 4).map((option, index) => (
              <Check key={option.value || index} $round $on={index === 0}>
                <i />
                <span>{(option.label && (option.label[locale] || option.label.default || option.label.en)) || option.value}</span>
              </Check>
            ))}
          </div>
        </FieldCell>
      );
    }
    const isSelect = ["country", "province", "select"].includes(field.type);
    return (
      <FieldCell key={field.key} $full={full}>
        {labelNode}
        <Input $tall={field.type === "textarea"}>
          <span style={{ overflow: "hidden", textOverflow: "ellipsis" }}>
            {field.type === "date" ? "dd / mm / yyyy" : placeholder || (isSelect ? tx("placeholder_province") : "")}
          </span>
          {isSelect && <span aria-hidden="true">▾</span>}
        </Input>
      </FieldCell>
    );
  };

  const renderBlock = (block) => {
    const settings = block.settings || {};
    switch (block.type) {
      case "order_summary": {
        const before = settings.show_compare_at !== false ? FIXTURE.compare_at_cents : FIXTURE.price_cents;
        return (
          <SummaryCard key={block.id}>
            <SummaryHead>
              <b>{tx("summary_title") || "Order summary"}</b>
              <Muted style={{ flex: 1 }}>{fill(tx("item_singular") || "{count} item", { count: 1 })}</Muted>
              {before > FIXTURE.price_cents && <s>{money(before)}</s>}
              <strong>{money(FIXTURE.price_cents)}</strong>
              <span aria-hidden="true" style={{ color: "var(--cf-muted)" }}>{express ? "›" : "⌄"}</span>
            </SummaryHead>
            {before > FIXTURE.price_cents && (
              <SaveStrip>{fill(tx(express ? "saved_so_far" : "you_save") || "You save {total}", { total: money(before - FIXTURE.price_cents) })} 🎉</SaveStrip>
            )}
          </SummaryCard>
        );
      }
      case "quantity_offer":
        return (
          <div key={block.id}>
            <SectionTitle style={{ textAlign: "center" }}>{tx("offer_qty_title") || "Buy more, save more"}</SectionTitle>
            <Tiers style={{ gridTemplateColumns: `repeat(${FIXTURE.tiers.length}, minmax(0, 1fr))` }}>
              {FIXTURE.tiers.map((tier) => {
                const regular = FIXTURE.compare_at_cents * tier.quantity;
                const price = Math.round(FIXTURE.price_cents * tier.quantity * (1 - tier.percent / 100));
                return (
                  <Tier key={tier.label} $on={tier.selected} $badge={!!tier.badge}>
                    {tier.badge && <TierBadge>{tx(tier.badge === "Best value" ? "tier_badge_best" : "tier_badge_popular") || tier.badge}</TierBadge>}
                    <span style={{ fontWeight: 700 }}>
                      {fill(tx(tier.quantity === 1 ? "tier_pack_one" : "tier_pack_other") || tier.label, { count: tier.quantity })}
                    </span>
                    {tier.quantity > 1 && FIXTURE.tiers.length < 3 && (
                      <Muted>{fill(tx("tier_each") || "{total} each", { total: money(Math.round(price / tier.quantity)) })}</Muted>
                    )}
                    <span style={{ display: "flex", flexWrap: "wrap", justifyContent: "center", alignItems: "baseline", gap: "0 6px" }}>
                      <strong>{money(price)}</strong>
                      <Muted style={{ textDecoration: "line-through" }}>{money(regular)}</Muted>
                    </span>
                    <SaveChip>{fill(tx("tier_save") || "Save {total}", { total: money(regular - price) })}</SaveChip>
                  </Tier>
                );
              })}
            </Tiers>
          </div>
        );
      case "fields": {
        const group = settings.group;
        const list = fields.filter((field) => field.group === group && visibleField(field));
        if (list.length === 0) return null;
        return (
          <div key={block.id}>
            {settings.title_key && tx(settings.title_key) && <SectionTitle>{tx(settings.title_key)}</SectionTitle>}
            <FieldsGrid>{list.map(renderField)}</FieldsGrid>
          </div>
        );
      }
      case "shipping": {
        const rates = FIXTURE.shipping;
        return (
          <div key={block.id}>
            <SectionTitle>{tx("shipping_title")}</SectionTitle>
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {rates.map((rate, index) => (
                <Option key={rate.id} $on={index === 0}>
                  <Check $round $on={index === 0}>
                    <i />
                    <span>
                      <span style={{ display: "block", fontWeight: 600 }}>{rate.name}</span>
                      <Muted>{rate.description}</Muted>
                    </span>
                  </Check>
                  <span>{rate.price_cents === 0 ? tx("shipping_free") : money(rate.price_cents)}</span>
                </Option>
              ))}
            </div>
          </div>
        );
      }
      case "bumps":
        return (
          <Option key={block.id}>
            <Check>
              <i />
              <span>
                <span style={{ display: "block", fontWeight: 600 }}>{FIXTURE.bump.title}</span>
                <Muted>{FIXTURE.bump.description}</Muted>
              </span>
            </Check>
            <span>+{money(FIXTURE.bump.price_cents)}</span>
          </Option>
        );
      case "discount":
        return (
          <div key={block.id} style={{ display: "flex", gap: 8 }}>
            <Input style={{ flex: 1 }}>{tx("discount_placeholder")}</Input>
            <Surface style={{ display: "flex", alignItems: "center", fontWeight: 600 }}>{tx("discount_apply")}</Surface>
          </div>
        );
      case "totals":
        return (
          <Surface key={block.id}>
            <Row>
              <Muted>{tx("subtotal")}</Muted>
              <span>{money(subtotal)}</span>
            </Row>
            <Row>
              <Muted>{tx("shipping")}</Muted>
              <span>{money(shipping)}</span>
            </Row>
            {settings.show_tax_line && (
              <Row>
                <Muted>{tx("tax")}</Muted>
                <span>{money(0)}</span>
              </Row>
            )}
            <Row style={{ marginTop: 6, fontWeight: 700, fontSize: 16 }}>
              <span>{tx("total")}</span>
              <span>{money(total)}</span>
            </Row>
          </Surface>
        );
      case "rich_text":
        return (
          <div key={block.id} style={{ color: "var(--cf-text)" }}>
            {stripTags(settings.html) || tx(`block_${block.id}_text`) || "Rich text"}
          </div>
        );
      case "image":
        return settings.url ? (
          <img key={block.id} src={settings.url} alt={settings.alt || ""} style={{ maxWidth: "100%", borderRadius: "var(--cf-field-radius)" }} />
        ) : (
          <Surface key={block.id} style={{ textAlign: "center", color: "var(--cf-muted)" }}>
            Image
          </Surface>
        );
      case "trust_badges":
        return (
          <div key={block.id} style={{ display: "flex", flexWrap: "wrap", gap: 8, justifyContent: "center" }}>
            {(settings.items || []).map((item, index) => (
              <Badge key={index}>
                <span aria-hidden="true">✓</span> {item.text}
              </Badge>
            ))}
          </div>
        );
      case "countdown":
        return (
          <Surface key={block.id} style={{ textAlign: "center" }}>
            {tx(settings.text_key || `block_${block.id}_text`) || ""}{" "}
            <strong>{String(Number(settings.minutes) || 10).padStart(2, "0")}:00</strong>
          </Surface>
        );
      case "threshold_bar":
        return (
          <ThresholdCard key={block.id}>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <span aria-hidden="true" style={{ width: 36, height: 36, borderRadius: 8, display: "grid", placeItems: "center", background: "var(--cf-bg)", fontSize: 18 }}>
                🚚
              </span>
              <strong style={{ fontSize: 13 }}>{fill(tx("threshold_ship_progress") || "Add {remaining} more for free shipping", vars)}</strong>
            </div>
            <Bar />
            <Row>
              <Muted>{money(FIXTURE.threshold_cents - 50000)}</Muted>
              <Muted>{money(FIXTURE.threshold_cents)}</Muted>
            </Row>
          </ThresholdCard>
        );
      default:
        return null;
    }
  };

  const submitBlock = blocks.find((block) => block.type === "submit");
  const submitLabel =
    submitBlock && submitBlock.settings && submitBlock.settings.show_total_in_button === false
      ? fill(tx("submit"), { ...vars, total: "" }).replace(/[\s—–-]+$/, "")
      : fill(tx("submit"), vars);

  const footer = (
    <Footer $sticky={!!design.sticky_submit}>
      <Submit>{submitLabel}</Submit>
      {config.pay_online && config.pay_online.enabled !== false && (
        <span data-pay style={{ color: "var(--cf-primary)", textDecoration: "underline" }}>{tx("pay_online")}</span>
      )}
      {!hidePoweredBy && <Muted>{tx("powered_by")}</Muted>}
    </Footer>
  );

  const headerNode = (
    <Header>
      {header.logo_url ? <img src={header.logo_url} alt="" /> : null}
      {header.show_title !== false ? <strong>{view === "otp" ? tx("otp_title") : view === "thankyou" ? tx("thank_you_title") : tx("title")}</strong> : <span style={{ flex: 1 }} />}
      <span data-close aria-hidden="true">
        {express ? (
          <svg width="18" height="16" viewBox="0 0 21 19" fill="currentColor">
            <path d="M17 11a1 1 0 000-2zM.4 9.36a1 1 0 000 1.41l6.4 6.34a1 1 0 001.4-1.42l-5.68-5.63 5.63-5.68a1 1 0 00-1.42-1.41zM17 9l-15.9.06v2L17 11z" />
          </svg>
        ) : (
          "✕"
        )}
      </span>
    </Header>
  );

  if (view === "otp") {
    return (
      <Skin $d={design} $mobile={mobile} dir={rtl ? "rtl" : "ltr"}>
        {headerNode}
        <Body>
          <Muted style={{ fontSize: 14 }}>{fill(tx("otp_subtitle"), vars)}</Muted>
          <div style={{ display: "flex", gap: 8, justifyContent: "center" }}>
            {[0, 1, 2, 3, 4, 5].map((index) => (
              <Input key={index} style={{ width: 40, justifyContent: "center" }}>
                {index < 2 ? "•" : ""}
              </Input>
            ))}
          </div>
          <Submit>{tx("otp_verify")}</Submit>
          <Row>
            <Muted>{fill(tx("otp_resend_in"), vars)}</Muted>
            <span style={{ color: "var(--cf-primary)" }}>{tx("otp_change_number")}</span>
          </Row>
        </Body>
      </Skin>
    );
  }

  if (view === "thankyou") {
    const thankYou = config.thank_you || {};
    const message = (thankYou.message && (thankYou.message[locale] || thankYou.message[language] || thankYou.message.en)) || tx("thank_you_message");
    return (
      <Skin $d={design} $mobile={mobile} dir={rtl ? "rtl" : "ltr"}>
        {headerNode}
        <Body style={{ textAlign: "center", alignItems: "center" }}>
          <div
            style={{ width: 56, height: 56, borderRadius: "50%", background: "var(--cf-primary)", color: "var(--cf-on-primary)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28 }}
            aria-hidden="true"
          >
            ✓
          </div>
          {thankYou.type === "order_status" ? (
            <Muted style={{ fontSize: 14 }}>Shopify order status page</Muted>
          ) : thankYou.type === "custom_url" ? (
            <Muted style={{ fontSize: 14, wordBreak: "break-all" }}>{fill(thankYou.url, vars) || "https://"}</Muted>
          ) : (
            <div style={{ fontSize: 15 }}>{fill(message, vars)}</div>
          )}
          <Surface style={{ width: "100%" }}>
            <Row>
              <span>{fill(tx("thank_you_order"), vars)}</span>
              <strong>{money(total)}</strong>
            </Row>
          </Surface>
          {thankYou.type === "whatsapp" ? (
            <Submit style={{ width: "100%" }}>{tx("thank_you_whatsapp")}</Submit>
          ) : (
            <Submit style={{ width: "100%" }}>{tx("thank_you_continue")}</Submit>
          )}
        </Body>
      </Skin>
    );
  }

  return (
    <Skin $d={design} $mobile={mobile} dir={rtl ? "rtl" : "ltr"}>
      {headerNode}
      <Body>{blocks.filter((block) => block.type !== "submit").map(renderBlock)}</Body>
      {footer}
    </Skin>
  );
};

export default FormMock;
