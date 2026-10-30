import React, { useContext, useEffect, useState } from "react";
import {
  Box,
  BlockStack,
  InlineStack,
  Text,
  Badge,
  Button,
  Card,
  Modal,
  TextField,
  Banner,
  List,
} from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";

const EXCLUDED_SHOPIFY_PLANS = /staff|partner|dev|affiliate|sandbox/i;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

const RabbitExpressCard = ({ onVisibilityChange }) => {
  const {
    shop: [shop],
  } = useContext(StoreContext);

  const [eligible, setEligible] = useState(false);
  const [alreadySubmitted, setAlreadySubmitted] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [phoneNumber, setPhoneNumber] = useState("");
  const [email, setEmail] = useState("");
  const [phoneError, setPhoneError] = useState("");
  const [emailError, setEmailError] = useState("");
  const [generalError, setGeneralError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [justSubmitted, setJustSubmitted] = useState(false);

  const shopifyPlan = (shop?.shopify_plan || shop?.shopifyPlan || "")
    .toString()
    .toLowerCase();
  const clientGatePassed =
    shop?.country_code === "IN" && !EXCLUDED_SHOPIFY_PLANS.test(shopifyPlan);

  useEffect(() => {
    if (!shop?.id || !clientGatePassed) return;
    let cancelled = false;
    Api.get("/api/rabbit_express_leads/eligibility")
      .then((response) => {
        if (cancelled) return;
        const data = response?.data || {};
        setEligible(!!data.eligible);
        setAlreadySubmitted(!!data.alreadySubmitted);
        setPhoneNumber(data.ownerPhone || shop?.owner_phone || "");
        setEmail(data.ownerEmail || shop?.owner_email || "");
      })
      .catch(() => {
        if (!cancelled) setEligible(false);
      });
    return () => {
      cancelled = true;
    };
  }, [shop?.id, clientGatePassed]);

  const visible = clientGatePassed && eligible && !dismissed;

  useEffect(() => {
    if (onVisibilityChange) onVisibilityChange(visible);
  }, [visible, onVisibilityChange]);

  if (!visible) return null;

  const handleSubmit = async () => {
    const trimmedPhone = phoneNumber.trim();
    const trimmedEmail = email.trim();
    let hasError = false;

    if (!trimmedPhone) {
      setPhoneError("Please enter your phone number.");
      hasError = true;
    } else if (!/^[+]?[\d\s()-]{8,16}$/.test(trimmedPhone)) {
      setPhoneError("Please enter a valid phone number.");
      hasError = true;
    } else {
      setPhoneError("");
    }

    if (!trimmedEmail) {
      setEmailError("Please enter your email address.");
      hasError = true;
    } else if (!EMAIL_PATTERN.test(trimmedEmail)) {
      setEmailError("Please enter a valid email address.");
      hasError = true;
    } else {
      setEmailError("");
    }

    if (hasError) return;

    setGeneralError("");
    setIsSubmitting(true);
    try {
      const response = await Api.post("/api/rabbit_express_leads", {
        rabbit_express_lead: {
          phone_number: trimmedPhone,
          email: trimmedEmail,
        },
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
      <Box paddingBlockEnd="500">
        <Card padding="0">
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
                    Rabbit Express — shipping for COD stores
                  </Text>
                  <Badge tone="attention" size="small">
                    Launch Offer
                  </Badge>
                </InlineStack>
                <Text variant="bodySm" as="p" tone="subdued">
                  Get our best shipping rates · no onboarding or platform fees ·
                  a support team that actually picks up.
                </Text>
              </BlockStack>
              {alreadySubmitted ? (
                <Badge tone="success">We'll reach out soon</Badge>
              ) : (
                <InlineStack gap="200" blockAlign="center" wrap={false}>
                  <Button
                    variant="primary"
                    size="slim"
                    onClick={() => setIsModalOpen(true)}
                  >
                    Get early access
                  </Button>
                  <Button
                    variant="tertiary"
                    size="slim"
                    onClick={() => setDismissed(true)}
                    accessibilityLabel="Dismiss Rabbit Express offer"
                  >
                    Not now
                  </Button>
                </InlineStack>
              )}
            </InlineStack>
          </Box>
        </Card>
      </Box>

      <Modal
        open={isModalOpen}
        onClose={() => !isSubmitting && setIsModalOpen(false)}
        title="Get Rabbit Express early access"
        primaryAction={{
          content: "Get early access",
          onAction: handleSubmit,
          loading: isSubmitting,
          disabled: isSubmitting || justSubmitted,
        }}
        secondaryActions={[
          {
            content: "Cancel",
            onAction: () => setIsModalOpen(false),
            disabled: isSubmitting,
          },
        ]}
      >
        <Modal.Section>
          <BlockStack gap="400">
            {justSubmitted && (
              <Banner tone="success">
                Thanks! Our team will call you shortly with your Rabbit Express
                rate card and launch pricing.
              </Banner>
            )}
            {generalError && (
              <Banner tone="critical" onDismiss={() => setGeneralError("")}>
                {generalError}
              </Banner>
            )}
            <List>
              <List.Item>
                <b>Best shipping rates</b> — launch pricing locked in for early
                stores, across every serviceable pincode in India
              </List.Item>
              <List.Item>
                <b>No onboarding fees</b> — no setup cost, no platform fee, no
                minimum volume, no lock-in
              </List.Item>
              <List.Item>
                <b>Support that answers</b> — a dedicated person for pickups,
                NDR follow-ups and weight disputes
              </List.Item>
            </List>
            <TextField
              label="Phone number"
              value={phoneNumber}
              onChange={(value) => {
                setPhoneNumber(value);
                if (phoneError) setPhoneError("");
              }}
              error={phoneError}
              type="tel"
              autoComplete="tel"
              disabled={isSubmitting || justSubmitted}
            />
            <TextField
              label="Email address"
              value={email}
              onChange={(value) => {
                setEmail(value);
                if (emailError) setEmailError("");
              }}
              error={emailError}
              type="email"
              autoComplete="email"
              helpText="We'll share your rate card on these. No commitment."
              disabled={isSubmitting || justSubmitted}
            />
          </BlockStack>
        </Modal.Section>
      </Modal>
    </React.Fragment>
  );
};

export default RabbitExpressCard;
