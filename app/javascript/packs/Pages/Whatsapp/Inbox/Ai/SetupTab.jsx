import React from "react";
import { BlockStack, Box, Card, Checkbox, ChoiceList, InlineGrid, Select, Text, TextField } from "@shopify/polaris";
import { t } from "../format";

const SKILLS = [
  {
    key: "order_status",
    label: () => t("ai.skill_order_status", "Order status"),
    help: () => t("ai.skill_order_status_help", "Answers \"where is my order\" with the real status and tracking link."),
  },
  {
    key: "cod_confirmation",
    label: () => t("ai.skill_cod", "COD confirmation"),
    help: () =>
      t(
        "ai.skill_cod_help",
        "When a customer types \"yes\", \"haan\" or \"confirm\" instead of tapping the button, the AI confirms their pending COD order.",
      ),
  },
  {
    key: "product_help",
    label: () => t("ai.skill_product", "Product questions and carts"),
    help: () =>
      t(
        "ai.skill_product_help",
        "Explains products from your Shopify catalog and the customer's abandoned cart, and shares the checkout link.",
      ),
  },
  {
    key: "place_orders",
    label: () => t("ai.skill_place_orders", "Take COD orders in chat"),
    help: () =>
      t(
        "ai.skill_place_orders_help",
        "When a customer says \"order kar do\", the AI collects the product, size, quantity, name and address, confirms the summary and places a COD order in Shopify.",
      ),
  },
  {
    key: "store_faq",
    label: () => t("ai.skill_faq", "Store questions"),
    help: () => t("ai.skill_faq_help", "Shipping, COD charges, returns and contact details, answered only from your Knowledge tab."),
  },
  {
    key: "pay_online",
    label: () => t("ai.skill_pay", "Pay online"),
    help: () =>
      t("ai.skill_pay_help", "Sends the prepaid payment link when a customer wants to pay online for a COD order."),
  },
  {
    key: "discounts",
    label: () => t("ai.skill_discounts", "Discount codes"),
    help: () =>
      t(
        "ai.skill_discounts_help",
        "Gives one discount code when a customer asks for a discount or hesitates on price, including abandoned carts. Never more than your limit, once per customer.",
      ),
  },
];

const HANDOFF_TOPICS = () =>
  t(
    "ai.handoff_topics",
    "Returns, refunds, exchanges, address changes, complaints, photos and voice notes, requests for a person, and anything the AI isn't sure about.",
  );

const SetupTab = ({ form, update, settings, storeName }) => {
  const skills = form.skills || {};
  const discount = form.discount || {};
  const setSkill = (key, value) => update({ skills: { ...skills, [key]: value } });
  const setDiscount = (key, value) => update({ discount: { ...discount, [key]: value } });
  const maxPercent = settings.limits?.max_discount_percent || 50;

  return (
    <BlockStack gap="400">
      <Card>
        <BlockStack gap="300">
          <Text as="h3" variant="headingSm">
            {t("ai.reply_mode_title", "How the AI replies")}
          </Text>
          <ChoiceList
            title={t("ai.reply_mode_title", "How the AI replies")}
            titleHidden
            selected={[form.reply_mode]}
            onChange={([value]) => update({ reply_mode: value })}
            choices={[
              {
                label: t("ai.reply_auto", "Send replies automatically"),
                value: "auto",
                helpText: t("ai.reply_auto_help", "Customers get an answer in seconds, day and night."),
              },
              {
                label: t("ai.reply_draft", "Draft only"),
                value: "draft",
                helpText: t(
                  "ai.reply_draft_help",
                  "The AI writes a draft in the inbox and your team sends it. Orders aren't changed in this mode.",
                ),
              },
            ]}
          />
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="300">
          <Text as="h3" variant="headingSm">
            {t("ai.persona_title", "Name and tone")}
          </Text>
          <InlineGrid columns={{ xs: 1, md: 2 }} gap="300">
            <TextField
              label={t("ai.agent_name", "Assistant name")}
              value={form.agent_name || ""}
              placeholder={t("ai.agent_name_placeholder", "%{store} Assistant", { store: storeName || "Store" })}
              onChange={(value) => update({ agent_name: value })}
              maxLength={40}
              autoComplete="off"
            />
            <Select
              label={t("ai.tone", "Tone")}
              options={[
                { label: t("ai.tone_friendly", "Friendly"), value: "friendly" },
                { label: t("ai.tone_professional", "Professional"), value: "professional" },
              ]}
              value={form.tone}
              onChange={(value) => update({ tone: value })}
            />
          </InlineGrid>
          <Text as="p" tone="subdued" variant="bodySm">
            {t("ai.language_note", "The AI replies in the customer's language, including Hinglish.")}
          </Text>
          <Select
            label={t("ai.daily_limit", "Most AI replies per customer per day")}
            options={[
              { label: "20", value: "20" },
              { label: t("ai.daily_limit_40", "40 (recommended)"), value: "40" },
              { label: "100", value: "100" },
              { label: t("ai.daily_limit_none", "No limit"), value: "0" },
            ]}
            value={String(form.daily_reply_limit ?? 40)}
            onChange={(value) => update({ daily_reply_limit: Number(value) })}
            helpText={t(
              "ai.daily_limit_help",
              "Protects your credits from spam or endless chats. After the limit, that customer's messages wait for your team until the next day.",
            )}
          />
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="300">
          <BlockStack gap="100">
            <Text as="h3" variant="headingSm">
              {t("ai.skills_title", "What the AI handles")}
            </Text>
            <Text as="p" tone="subdued">
              {t("ai.skills_body", "Turn off anything you'd rather answer yourself. Those chats go to your team.")}
            </Text>
          </BlockStack>
          {SKILLS.map((skill) => (
            <Box
              key={skill.key}
              padding="300"
              borderWidth="025"
              borderColor="border-secondary"
              borderRadius="200"
            >
              <BlockStack gap="200">
                <Checkbox
                  label={skill.label()}
                  helpText={skill.help()}
                  checked={!!skills[skill.key]}
                  onChange={(value) => setSkill(skill.key, value)}
                />
                {skill.key === "cod_confirmation" && skills.cod_confirmation && (
                  <Box paddingInlineStart="600">
                    <Checkbox
                      label={t("ai.allow_cancel", "Also cancel orders when the customer clearly asks")}
                      helpText={t(
                        "ai.allow_cancel_help",
                        "Off: cancellation requests go to your team with a Cancel request label.",
                      )}
                      checked={!!form.allow_cancel}
                      onChange={(value) => update({ allow_cancel: value })}
                    />
                  </Box>
                )}
                {skill.key === "discounts" && skills.discounts && (
                  <Box paddingInlineStart="600">
                    <InlineGrid columns={{ xs: 1, md: 3 }} gap="300">
                      <TextField
                        type="number"
                        label={t("ai.discount_max", "Discount")}
                        suffix="%"
                        min={1}
                        max={maxPercent}
                        value={String(discount.max_percent ?? "")}
                        onChange={(value) => setDiscount("max_percent", value === "" ? "" : Number(value))}
                        helpText={t("ai.discount_max_help", "Up to %{max}%", { max: maxPercent })}
                        autoComplete="off"
                      />
                      <TextField
                        type="number"
                        label={t("ai.discount_min", "Minimum cart value")}
                        min={0}
                        value={String(discount.min_cart_value ?? "")}
                        onChange={(value) => setDiscount("min_cart_value", value === "" ? "" : Number(value))}
                        helpText={t("ai.discount_min_help", "0 means any cart")}
                        autoComplete="off"
                      />
                      <TextField
                        type="number"
                        label={t("ai.discount_expiry", "Code valid for")}
                        suffix={t("ai.hours", "hours")}
                        min={1}
                        max={168}
                        value={String(discount.expiry_hours ?? "")}
                        onChange={(value) => setDiscount("expiry_hours", value === "" ? "" : Number(value))}
                        autoComplete="off"
                      />
                    </InlineGrid>
                  </Box>
                )}
              </BlockStack>
            </Box>
          ))}
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="300">
          <Text as="h3" variant="headingSm">
            {t("ai.handoff_title", "Handing over to your team")}
          </Text>
          <Text as="p" tone="subdued">
            {t("ai.handoff_body", "The AI always passes these to your team:")} {HANDOFF_TOPICS()}
          </Text>
          <TextField
            label={t("ai.handoff_text", "Message the customer gets when the AI hands over")}
            value={form.handoff_text || ""}
            onChange={(value) => update({ handoff_text: value })}
            multiline={2}
            maxLength={500}
            showCharacterCount
            autoComplete="off"
          />
          <Select
            label={t("ai.team_timeout", "If your team doesn't reply, the AI steps back in after")}
            options={[
              { label: t("ai.timeout_15", "15 minutes"), value: "15" },
              { label: t("ai.timeout_30", "30 minutes"), value: "30" },
              { label: t("ai.timeout_60", "1 hour"), value: "60" },
              { label: t("ai.timeout_120", "2 hours"), value: "120" },
              { label: t("ai.timeout_never", "Never, wait for the team"), value: "0" },
            ]}
            value={String(form.team_timeout_minutes ?? 30)}
            onChange={(value) => update({ team_timeout_minutes: Number(value) })}
            helpText={t(
              "ai.team_timeout_help",
              "Counts from the customer's message. Applies after a handover or a team reply; chats you pause yourself stay with your team.",
            )}
          />
          <Text as="p" tone="subdued" variant="bodySm">
            {t(
              "ai.handoff_note",
              "Handed-over chats are labelled, get a note with what the customer needs, and stay with your team until resolved.",
            )}
          </Text>
        </BlockStack>
      </Card>
    </BlockStack>
  );
};

export default SetupTab;
