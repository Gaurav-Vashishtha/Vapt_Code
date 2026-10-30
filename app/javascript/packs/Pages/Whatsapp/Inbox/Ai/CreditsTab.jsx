import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  Badge,
  Banner,
  BlockStack,
  Box,
  Button,
  Card,
  Checkbox,
  DataTable,
  InlineGrid,
  InlineStack,
  Select,
  SkeletonBodyText,
  Text,
} from "@shopify/polaris";
import { errorMessage, t } from "../format";
import { aiApi, formatCredits } from "./api";

const KIND_LABELS = {
  grant: () => t("ai.tx_grant", "Free credits"),
  purchase: () => t("ai.tx_purchase", "Credit pack"),
  auto_recharge: () => t("ai.tx_auto", "Auto-recharge"),
  refund: () => t("ai.tx_refund", "Refund"),
  adjust: () => t("ai.tx_adjust", "Adjustment"),
};

const STATUS_TONES = { completed: "success", declined: undefined, failed: "critical", processing: "info" };

const readChargeId = () => {
  try {
    return new URLSearchParams(window.location.search).get("charge_id");
  } catch (e) {
    return null;
  }
};

const clearChargeId = () => {
  try {
    const url = new URL(window.location.href);
    url.searchParams.delete("charge_id");
    window.history.replaceState(window.history.state, "", `${url.pathname}${url.search}`);
  } catch (e) {
    // URL API unavailable: leaving the param only re-runs an idempotent confirm.
  }
};

const perReply = (pack) => (pack.price_usd / pack.credits).toFixed(3);

const CreditsTab = ({ wallet: initialWallet, onWallet }) => {
  const [data, setData] = useState(null);
  const [buying, setBuying] = useState(null);
  const [savingAuto, setSavingAuto] = useState(false);
  const [notice, setNotice] = useState(null);
  const confirmed = useRef(false);

  const load = useCallback(async () => {
    try {
      const next = await aiApi.wallet();
      setData(next);
      onWallet(next.wallet);
    } catch (e) {
      setNotice({ tone: "critical", text: errorMessage(e) });
    }
  }, [onWallet]);

  useEffect(() => {
    const chargeId = readChargeId();
    if (!chargeId || confirmed.current) {
      load();
      return;
    }
    confirmed.current = true;
    aiApi
      .confirmPurchase(chargeId)
      .then((res) => {
        if (res.status === "completed") {
          setNotice({
            tone: "success",
            text: t("ai.purchase_done", "%{count} credits added. Thank you!", { count: formatCredits(res.credits) }),
          });
        } else if (res.status === "declined") {
          setNotice({ tone: "warning", text: t("ai.purchase_declined", "The purchase was declined in Shopify. No charge was made.") });
        } else {
          setNotice({
            tone: "info",
            text: t("ai.purchase_pending", "Shopify is still processing your purchase. Credits appear here within a few minutes."),
          });
        }
      })
      .catch((e) => setNotice({ tone: "critical", text: errorMessage(e) }))
      .finally(() => {
        clearChargeId();
        load();
      });
  }, [load]);

  const buy = async (pack) => {
    setBuying(pack.key);
    setNotice(null);
    try {
      const res = await aiApi.buy(pack.key);
      window.open(res.confirmation_url, "_top");
    } catch (e) {
      setNotice({ tone: "critical", text: errorMessage(e) });
      setBuying(null);
    }
  };

  const saveAuto = async (patch) => {
    setSavingAuto(true);
    setNotice(null);
    try {
      const next = await aiApi.saveWallet(patch);
      setData(next);
      onWallet(next.wallet);
    } catch (e) {
      setNotice({ tone: "critical", text: errorMessage(e) });
    } finally {
      setSavingAuto(false);
    }
  };

  const wallet = data?.wallet || initialWallet;
  const packs = wallet?.packs || [];

  return (
    <BlockStack gap="400">
      {notice && (
        <Banner tone={notice.tone} onDismiss={() => setNotice(null)}>
          {notice.text}
        </Banner>
      )}
      <Card>
        <InlineStack align="space-between" blockAlign="center" gap="400">
          <BlockStack gap="100">
            <Text as="p" tone="subdued">
              {t("ai.balance", "AI credit balance")}
            </Text>
            <Text as="p" variant="heading2xl">
              {formatCredits(wallet?.balance)}
            </Text>
            <Text as="p" tone="subdued" variant="bodySm">
              {t(
                "ai.credit_rule",
                "1 credit = 1 message the AI writes (reply, handover message or draft). Testing is free. Credits never expire.",
              )}
            </Text>
          </BlockStack>
          {data?.usage && (
            <BlockStack gap="100" inlineAlign="end">
              <Text as="p" tone="subdued">
                {t("ai.used_30d", "Used in the last 30 days")}
              </Text>
              <Text as="p" variant="headingLg">
                {formatCredits(data.usage.credits_30d)}
              </Text>
            </BlockStack>
          )}
        </InlineStack>
      </Card>

      <Card>
        <BlockStack gap="300">
          <Text as="h3" variant="headingSm">
            {t("ai.buy_title", "Buy credits")}
          </Text>
          <InlineGrid columns={{ xs: 1, md: 3 }} gap="300">
            {packs.map((pack, index) => (
              <Box key={pack.key} padding="400" borderWidth="025" borderColor="border" borderRadius="300">
                <BlockStack gap="200">
                  <InlineStack align="space-between" blockAlign="center">
                    <Text as="p" variant="headingMd">
                      {t("ai.pack_credits", "%{count} replies", { count: formatCredits(pack.credits) })}
                    </Text>
                    {index === 1 && <Badge tone="success">{t("ai.popular", "Popular")}</Badge>}
                  </InlineStack>
                  <Text as="p" variant="headingXl">
                    ${pack.price_usd}
                  </Text>
                  <Text as="p" tone="subdued" variant="bodySm">
                    {t("ai.per_reply", "$%{price} per reply", { price: perReply(pack) })}
                  </Text>
                  <Button
                    variant={index === 1 ? "primary" : "secondary"}
                    onClick={() => buy(pack)}
                    loading={buying === pack.key}
                    disabled={!!buying && buying !== pack.key}
                    fullWidth
                  >
                    {t("ai.buy", "Buy")}
                  </Button>
                </BlockStack>
              </Box>
            ))}
          </InlineGrid>
          <Text as="p" tone="subdued" variant="bodySm">
            {t(
              "ai.buy_note",
              "You'll approve a one-time charge in Shopify. It's added to your next Shopify bill and the credits appear here right away.",
            )}
          </Text>
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="300">
          <Text as="h3" variant="headingSm">
            {t("ai.auto_title", "Auto-recharge")}
          </Text>
          {!data ? (
            <SkeletonBodyText lines={2} />
          ) : (
            <>
              <Checkbox
                label={t("ai.auto_label", "Buy a pack automatically when credits drop below %{count}", {
                  count: wallet.low_balance,
                })}
                helpText={
                  data.auto_recharge_available
                    ? t("ai.auto_help", "Charged as usage on your COD King plan, so the agent never stops mid-day.")
                    : t("ai.auto_no_plan", "Needs an active COD King plan. Until then, buy packs above.")
                }
                checked={!!wallet.auto_recharge}
                disabled={!data.auto_recharge_available || savingAuto}
                onChange={(value) => saveAuto({ auto_recharge: value, auto_recharge_pack: wallet.auto_recharge_pack })}
              />
              {wallet.auto_recharge && (
                <Box maxWidth="320px">
                  <Select
                    label={t("ai.auto_pack", "Pack to buy")}
                    options={packs.map((p) => ({
                      label: `${formatCredits(p.credits)} — $${p.price_usd}`,
                      value: p.key,
                    }))}
                    value={wallet.auto_recharge_pack || packs[0]?.key}
                    disabled={savingAuto}
                    onChange={(value) => saveAuto({ auto_recharge: true, auto_recharge_pack: value })}
                  />
                </Box>
              )}
              {wallet.auto_recharge_error && (
                <Banner tone="warning">
                  {t(
                    "ai.auto_failed",
                    "The last auto-recharge didn't go through (%{reason}). Raise your plan's spending limit or buy a pack.",
                    { reason: wallet.auto_recharge_error.replace(/_/g, " ") },
                  )}
                </Banner>
              )}
            </>
          )}
        </BlockStack>
      </Card>

      <Card>
        <BlockStack gap="300">
          <Text as="h3" variant="headingSm">
            {t("ai.history", "History")}
          </Text>
          {!data ? (
            <SkeletonBodyText lines={3} />
          ) : data.transactions.length === 0 ? (
            <Text as="p" tone="subdued">
              {t("ai.history_empty", "No purchases yet.")}
            </Text>
          ) : (
            <DataTable
              columnContentTypes={["text", "text", "numeric", "numeric", "text"]}
              headings={[
                t("ai.col_date", "Date"),
                t("ai.col_type", "Type"),
                t("ai.col_credits", "Credits"),
                t("ai.col_amount", "Amount"),
                t("ai.col_status", "Status"),
              ]}
              rows={data.transactions.map((tx) => [
                new Date(tx.created_at).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" }),
                (KIND_LABELS[tx.kind] || KIND_LABELS.adjust)(),
                `${tx.credits > 0 ? "+" : ""}${formatCredits(tx.credits)}`,
                tx.amount_usd ? `$${tx.amount_usd}` : "—",
                <Badge key={tx.id} tone={STATUS_TONES[tx.status]}>
                  {tx.status}
                </Badge>,
              ])}
            />
          )}
        </BlockStack>
      </Card>
    </BlockStack>
  );
};

export default CreditsTab;
