import React, { useEffect, useState } from "react";
import {
  Card,
  BlockStack,
  InlineStack,
  Text,
  TextField,
  Button,
  Banner,
  Badge,
  Box,
} from "@shopify/polaris";
import Api from "../Services/Api";
import I18n from "../i18n-lang";

// Free pre-order OTP campaign coupon (ENV-driven, see PreOrderOtpCampaign on
// the backend). Renders nothing unless the campaign is configured AND either
// still active or already redeemed by this shop. Eligibility (installed inside
// the campaign window, no uninstall after start) is enforced server-side — the
// card just surfaces the error message.
const OtpCampaignCouponCard = () => {
  const [status, setStatus] = useState(null);
  const [code, setCode] = useState("");
  const [applying, setApplying] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    let mounted = true;
    Api.get("/plans/otp_campaign")
      .then((res) => mounted && setStatus(res.data))
      .catch(() => mounted && setStatus(null));
    return () => {
      mounted = false;
    };
  }, []);

  if (!status || !status.configured) return null;
  if (!status.active && !status.applied) return null;

  const handleApply = async () => {
    if (!code.trim() || applying) return;
    setApplying(true);
    setError("");
    try {
      const { data } = await Api.post("/plans/apply_otp_campaign_coupon", {
        code: code.trim(),
      });
      setStatus(data);
    } catch (err) {
      setError(
        err?.response?.data?.error ||
          "Could not apply the coupon. Please try again."
      );
    } finally {
      setApplying(false);
    }
  };

  const handleRemove = async () => {
    if (removing) return;
    setRemoving(true);
    setError("");
    try {
      const { data } = await Api.delete("/plans/remove_otp_campaign_coupon");
      setStatus(data);
      setCode("");
    } catch (err) {
      setError(
        err?.response?.data?.error ||
          "Could not remove the coupon. Please try again."
      );
    } finally {
      setRemoving(false);
    }
  };

  return (
    <Card>
      <BlockStack gap="300">
        <InlineStack gap="200" blockAlign="center">
          <Text variant="headingMd" as="h2">
            {I18n.t("otp_campaign_coupon_card.apply_coupon_code")}
          </Text>
          <Badge tone="success">{I18n.t("otp_campaign_coupon_card.limited_time")}</Badge>
        </InlineStack>

        {status.applied ? (
          <BlockStack gap="300">
            <Banner tone="success" title={I18n.t("otp_campaign_coupon_card.coupon_applied")}>
              <p>
                {I18n.t("otp_campaign_coupon_card.pre_order_otp_messages_to_india")}
              </p>
            </Banner>
            {error && (
              <Banner tone="critical" onDismiss={() => setError("")}>
                {error}
              </Banner>
            )}
            <InlineStack align="end">
              <Button
                variant="plain"
                tone="critical"
                onClick={handleRemove}
                loading={removing}
              >
                {I18n.t("otp_campaign_coupon_card.remove_coupon")}
              </Button>
            </InlineStack>
          </BlockStack>
        ) : (
          <>
            {error && (
              <Banner tone="critical" onDismiss={() => setError("")}>
                {error}
              </Banner>
            )}
            <InlineStack gap="200" blockAlign="end" wrap={false}>
              <Box minWidth="240px">
                <TextField
                  label={I18n.t("otp_campaign_coupon_card.coupon_code")}
                  labelHidden
                  value={code}
                  onChange={setCode}
                  autoComplete="off"
                  placeholder={I18n.t("otp_campaign_coupon_card.enter_coupon_code")}
                  disabled={applying}
                />
              </Box>
              <Button
                variant="primary"
                onClick={handleApply}
                loading={applying}
                disabled={!code.trim()}
              >
                {I18n.t("otp_campaign_coupon_card.apply")}
              </Button>
            </InlineStack>
          </>
        )}
      </BlockStack>
    </Card>
  );
};

export default OtpCampaignCouponCard;
