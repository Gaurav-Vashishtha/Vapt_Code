import React, { useContext, useEffect, useState } from "react";
import {
  Box,
  BlockStack,
  InlineStack,
  Text,
  Badge,
  Button,
  Modal,
  TextField,
  Banner,
  List,
  Divider,
} from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";
import I18n from "../i18n-lang";

const OneClickCheckoutCard = () => {
  const {
    shop: [shop],
  } = useContext(StoreContext);

  const [eligible, setEligible] = useState(false);
  const [alreadySubmitted, setAlreadySubmitted] = useState(false);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [phoneNumber, setPhoneNumber] = useState("");
  const [phoneError, setPhoneError] = useState("");
  const [generalError, setGeneralError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [justSubmitted, setJustSubmitted] = useState(false);

  const shopifyPlan = (shop?.shopify_plan || shop?.shopifyPlan || "")
    .toString()
    .toLowerCase();
  const clientGatePassed =
    shop?.country_code === "IN" &&
    !shopifyPlan.includes("staff") &&
    !shopifyPlan.includes("partner");

  useEffect(() => {
    if (!shop?.id || !clientGatePassed) return;
    let cancelled = false;
    Api.get("/api/one_click_checkout_leads/eligibility")
      .then((response) => {
        if (cancelled) return;
        const data = response?.data || {};
        setEligible(!!data.eligible);
        setAlreadySubmitted(!!data.alreadySubmitted);
        setPhoneNumber(data.ownerPhone || shop?.owner_phone || "");
      })
      .catch(() => {
        if (!cancelled) setEligible(false);
      });
    return () => {
      cancelled = true;
    };
  }, [shop?.id, clientGatePassed]);

  if (!clientGatePassed || !eligible) return null;

  const handleSubmit = async () => {
    const trimmed = phoneNumber.trim();
    if (!trimmed) {
      setPhoneError("Please enter your phone number.");
      return;
    }
    if (!/^[+]?[\d\s()-]{8,16}$/.test(trimmed)) {
      setPhoneError("Please enter a valid phone number.");
      return;
    }

    setPhoneError("");
    setGeneralError("");
    setIsSubmitting(true);
    try {
      const response = await Api.post("/api/one_click_checkout_leads", {
        one_click_checkout_lead: { phone_number: trimmed },
      });
      if (response?.data?.success) {
        setJustSubmitted(true);
        setAlreadySubmitted(true);
        setTimeout(() => setIsModalOpen(false), 2500);
      } else {
        setGeneralError("Something went wrong. Please try again.");
      }
    } catch (error) {
      if (error?.response?.data?.error === "already_submitted") {
        setAlreadySubmitted(true);
        setIsModalOpen(false);
      } else {
        setGeneralError("Something went wrong. Please try again.");
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <React.Fragment>
      <Divider />
      <Box paddingBlock="300" paddingInline="400">
        <InlineStack
          align="space-between"
          blockAlign="center"
          gap="300"
          wrap={false}
        >
          <BlockStack gap="050">
            <InlineStack gap="150" blockAlign="center">
              <Text variant="headingSm" as="h3">
                {I18n.t("one_click_checkout_card.one_click_checkout")}
              </Text>
              <Badge tone="attention" size="small">
                {I18n.t("one_click_checkout_card.launch_offer")}
              </Badge>
            </InlineStack>
            <Text variant="bodySm" as="p" tone="subdued">
              {I18n.t("one_click_checkout_card.lowest_transaction_fees_for_early_stores")}
            </Text>
          </BlockStack>
          {alreadySubmitted ? (
            <Badge tone="success">{I18n.t("one_click_checkout_card.we_ll_reach_out_soon")}</Badge>
          ) : (
            <Button
              variant="primary"
              size="slim"
              onClick={() => setIsModalOpen(true)}
            >
              {I18n.t("one_click_checkout_card.get_early_access")}
            </Button>
          )}
        </InlineStack>
      </Box>

      <Modal
        open={isModalOpen}
        onClose={() => !isSubmitting && setIsModalOpen(false)}
        title={I18n.t("one_click_checkout_card.get_one_click_checkout_early_access")}
        primaryAction={{
          content: I18n.t("one_click_checkout_card.get_early_access"),
          onAction: handleSubmit,
          loading: isSubmitting,
          disabled: isSubmitting || justSubmitted,
        }}
        secondaryActions={[
          {
            content: I18n.t("one_click_checkout_card.cancel"),
            onAction: () => setIsModalOpen(false),
            disabled: isSubmitting,
          },
        ]}
      >
        <Modal.Section>
          <BlockStack gap="400">
            {justSubmitted && (
              <Banner tone="success">
                {I18n.t("one_click_checkout_card.thanks_our_team_will_call_you")}
              </Banner>
            )}
            {generalError && (
              <Banner tone="critical" onDismiss={() => setGeneralError("")}>
                {generalError}
              </Banner>
            )}
            <List>
              <List.Item>
                <b>{I18n.t("one_click_checkout_card.lowest_transaction_fees")}</b> {I18n.t("one_click_checkout_card.locked_in_at_launch_pricing")}
              </List.Item>
              <List.Item>
                <b>{I18n.t("one_click_checkout_card.95_of_indian_customers")}</b> {I18n.t("one_click_checkout_card.check_out_with_pre_filled_addresses")}
              </List.Item>
              <List.Item>
                {I18n.t("one_click_checkout_card.stores_see")} <b>{I18n.t("one_click_checkout_card.up_to_37_more_completed_orders")}</b>
              </List.Item>
            </List>
            <TextField
              label={I18n.t("one_click_checkout_card.phone_number")}
              value={phoneNumber}
              onChange={(value) => {
                setPhoneNumber(value);
                if (phoneError) setPhoneError("");
              }}
              error={phoneError}
              type="tel"
              autoComplete="tel"
              helpText={I18n.t("one_click_checkout_card.we_ll_call_you_on_this")}
              disabled={isSubmitting || justSubmitted}
            />
          </BlockStack>
        </Modal.Section>
      </Modal>
    </React.Fragment>
  );
};

export default OneClickCheckoutCard;
