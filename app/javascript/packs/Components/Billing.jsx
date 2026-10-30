import React, {
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import {
  Page,
  Layout,
  Card,
  Text,
  BlockStack,
  InlineStack,
  InlineGrid,
  Box,
  Badge,
  Button,
  Select,
  TextField,
  DataTable,
  Collapsible,
  MediaCard,
  Link,
  Divider,
  VideoThumbnail,
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
  Banner,
} from "@shopify/polaris";
import {
  ChevronDownMinor,
  ChevronUpMinor,
  ExternalSmallMinor,
} from "@shopify/polaris-icons";
import { navigateTo } from "../../utils/navigate";
import Api from "../Services/Api";
import { StoreContext } from "../Context/Store";
import I18n from "../i18n-lang";
import FeatureCallout from "./FeatureCallout";
import BillingUsageRows from "../Pages/CodForm/components/BillingUsageRows";

const placeholderValue = "—";

const getBreakdownOptions = () => [
  { label: I18n.t("billing.last_7_days"), value: "7" },
  { label: I18n.t("billing.last_30_days"), value: "30" },
  { label: I18n.t("billing.last_90_days"), value: "90" },
];

const rangeOffsets = {
  "7": [0, 2, 4, 6],
  "30": [0, 7, 14, 21],
  "90": [0, 15, 30, 60],
};

const getSmsUsageDefinitions = () => [
  {
    id: "verification",
    title: I18n.t("billing.sms_verification_title"),
    description: I18n.t("billing.sms_verification_desc"),
    summaryPath: ["sms", "verification"],
  },
  {
    id: "confirmation",
    title: I18n.t("billing.sms_confirmation_title"),
    description: I18n.t("billing.sms_confirmation_desc"),
    summaryPath: ["sms", "confirmation"],
  },
  {
    id: "fulfilment",
    title: I18n.t("billing.sms_fulfilment_title"),
    description: I18n.t("billing.sms_fulfilment_desc"),
    summaryPath: ["sms", "fulfilment"],
  },
  {
    id: "preOrder",
    title: I18n.t("billing.sms_pre_order_title"),
    description: I18n.t("billing.sms_pre_order_desc"),
    summaryPath: ["sms", "preOrder"],
  },
  {
    id: "abandoned",
    title: I18n.t("billing.sms_abandoned_title"),
    description: I18n.t("billing.sms_abandoned_desc"),
    summaryPath: ["sms", "abandonedCart"],
  },
];

const getWhatsappUsageDefinitions = () => [
  {
    id: "whatsapp",
    title: I18n.t("billing.wa_verification_title"),
    description: I18n.t("billing.wa_verification_desc"),
    summaryPath: ["whatsapp", "whatsapp"],
  },
  {
    id: "whatsappCodPrepaid",
    title: I18n.t("billing.wa_cod_prepaid_title"),
    description: I18n.t("billing.wa_cod_prepaid_desc"),
    summaryPath: ["whatsapp", "whatsappCodPrepaid"],
  },
  {
    id: "whatsappFirstPurchase",
    title: I18n.t("billing.wa_first_purchase_title"),
    description: I18n.t("billing.wa_first_purchase_desc"),
    summaryPath: ["whatsapp", "whatsappFirstPurchase"],
  },
  {
    id: "whatsappConfirmation",
    title: I18n.t("billing.wa_confirmation_title"),
    description: I18n.t("billing.wa_confirmation_desc"),
    summaryPath: ["whatsapp", "whatsappConfirmation"],
  },
  {
    id: "whatsappFulfilment",
    title: I18n.t("billing.wa_fulfilment_title"),
    description: I18n.t("billing.wa_fulfilment_desc"),
    summaryPath: ["whatsapp", "whatsappFulfilment"],
  },
  {
    id: "preOrder",
    title: I18n.t("billing.wa_pre_order_title"),
    description: I18n.t("billing.wa_pre_order_desc"),
    summaryPath: ["whatsapp", "preOrder"],
  },
  {
    id: "abandoned",
    title: I18n.t("billing.wa_abandoned_title"),
    description: I18n.t("billing.wa_abandoned_desc"),
    summaryPath: ["whatsapp", "abandonedCart"],
  },
  {
    id: "bsp",
    title: I18n.t("billing.wa_bsp_title"),
    description: I18n.t("billing.wa_bsp_desc"),
    summaryPath: ["whatsapp", "bsp"],
  },
];

const Billing = () => {
  const {
    shop: [shop],
    plan: [plan],
    billingSnapshot: [billingSnapshot],
  } = useContext(StoreContext);

  const [selectedRange, setSelectedRange] = useState("7");
  const [startDate, setStartDate] = useState(() => {
    const date = new Date();
    date.setDate(date.getDate() - 7);
    return date.toISOString().split("T")[0];
  });
  const [endDate, setEndDate] = useState(() => {
    return new Date().toISOString().split("T")[0];
  });
  const [useDateRange, setUseDateRange] = useState(false);
  const [smsChargesOpen, setSmsChargesOpen] = useState(false);
  const [whatsappChargesOpen, setWhatsappChargesOpen] = useState(false);
  const [usageSummary, setUsageSummary] = useState(null);
  const [usageLoading, setUsageLoading] = useState(false);
  const [appliedSelectedRange, setAppliedSelectedRange] = useState("7");
  const [appliedStartDate, setAppliedStartDate] = useState(startDate);
  const [appliedEndDate, setAppliedEndDate] = useState(endDate);
  const [appliedUseDateRange, setAppliedUseDateRange] = useState(false);
  const [referralStatus, setReferralStatus] = useState(null);
  const [referralStatusLoading, setReferralStatusLoading] = useState(true);
  const [referralCode, setReferralCode] = useState("");
  const [referralApplying, setReferralApplying] = useState(false);
  const [referralUnlinking, setReferralUnlinking] = useState(false);
  const [referralBanner, setReferralBanner] = useState(null);

  const baseCurrency = "USD";
  const numberFormatter = useMemo(() => new Intl.NumberFormat("en-US"), []);
  const dateFormatter = useMemo(
    () =>
      new Intl.DateTimeFormat("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
      }),
    []
  );

  useEffect(() => {
    let isMounted = true;
    setUsageLoading(true);

    const params = appliedUseDateRange
      ? { start_date: appliedStartDate, end_date: appliedEndDate, shop: shop?.shopify_domain }
      : { days: appliedSelectedRange, shop: shop?.shopify_domain };

    Api.get("/billing/usage_summary", { params })
      .then((response) => {
        if (!isMounted) return;
        setUsageSummary(response?.data || null);
      })
      .catch((error) => {
        console.error("[Billing] Failed to load usage summary", error);
        if (isMounted) {
          setUsageSummary(null);
        }
      })
      .finally(() => {
        if (isMounted) {
          setUsageLoading(false);
        }
      });

    return () => {
      isMounted = false;
    };
  }, [appliedSelectedRange, appliedStartDate, appliedEndDate, appliedUseDateRange, shop?.shopify_domain]);

  useEffect(() => {
    if (!shop?.shopify_domain) {
      setReferralStatusLoading(false);
      return undefined;
    }
    let cancelled = false;
    setReferralStatusLoading(true);
    Api.get("/billing/referral_link", { params: { shop: shop.shopify_domain } })
      .then((response) => {
        if (!cancelled) {
          setReferralStatus(response?.data ?? null);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setReferralStatus(null);
        }
      })
      .finally(() => {
        if (!cancelled) {
          setReferralStatusLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [shop?.shopify_domain]);

  const applyReferralCode = useCallback(() => {
    const trimmed = referralCode.trim();
    if (!trimmed || !shop?.shopify_domain) return;
    setReferralApplying(true);
    setReferralBanner(null);
    Api.post(
      "/billing/referral_link",
      { referralCode: trimmed },
      { params: { shop: shop.shopify_domain } }
    )
      .then((response) => {
        const partnerName = response?.data?.partnerName;
        setReferralStatus({
          linked: true,
          approved: true,
          partnerName,
        });
        setReferralCode("");
      })
      .catch((error) => {
        const msg =
          error.response?.data?.error ||
          I18n.t("billing.referral_error_generic");
        setReferralBanner({ tone: "critical", message: msg });
      })
      .finally(() => {
        setReferralApplying(false);
      });
  }, [referralCode, shop?.shopify_domain]);

  const unlinkReferralCode = useCallback(() => {
    if (!shop?.shopify_domain) return;
    const confirmed = window.confirm(I18n.t("billing.referral_unlink_confirm"));
    if (!confirmed) return;

    setReferralUnlinking(true);
    setReferralBanner(null);
    Api.delete("/billing/referral_link", { params: { shop: shop.shopify_domain } })
      .then(() => {
        setReferralStatus({ linked: false });
        setReferralBanner({
          tone: "success",
          message: I18n.t("billing.referral_unlink_success"),
        });
      })
      .catch((error) => {
        const msg =
          error.response?.data?.error ||
          I18n.t("billing.referral_error_generic");
        setReferralBanner({ tone: "critical", message: msg });
      })
      .finally(() => {
        setReferralUnlinking(false);
      });
  }, [shop?.shopify_domain]);

  const applyDateFilter = useCallback(() => {
    setAppliedUseDateRange(useDateRange);
    setAppliedSelectedRange(selectedRange);
    setAppliedStartDate(startDate);
    setAppliedEndDate(endDate);
  }, [useDateRange, selectedRange, startDate, endDate]);

  const isApplyDisabled = useMemo(() => {
    if (useDateRange && (!startDate || !endDate || startDate > endDate)) {
      return true;
    }

    return (
      appliedUseDateRange === useDateRange &&
      appliedSelectedRange === selectedRange &&
      appliedStartDate === startDate &&
      appliedEndDate === endDate
    );
  }, [
    useDateRange,
    selectedRange,
    startDate,
    endDate,
    appliedUseDateRange,
    appliedSelectedRange,
    appliedStartDate,
    appliedEndDate,
  ]);

  const formatCurrencyValue = useCallback(
    (value, currency = baseCurrency, options = {}) => {
      if (value === null || value === undefined || Number.isNaN(Number(value))) {
        return null;
      }

      const numericValue = Number(value);
      const minimumFractionDigits =
        options.minimumFractionDigits ??
        (numericValue < 1 ? 4 : 2);
      const maximumFractionDigits =
        options.maximumFractionDigits ??
        (numericValue < 1 ? 4 : 2);

      return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency,
        minimumFractionDigits,
        maximumFractionDigits,
      }).format(numericValue);
    },
    [baseCurrency]
  );

  const formatPercent = (value) => {
    if (value === null || value === undefined || Number.isNaN(Number(value))) {
      return null;
    }
    return `${(Number(value) * 100).toFixed(2)}%`;
  };

  const planName =
    billingSnapshot?.planName || plan?.name || shop?.plan?.name;
  const planPrice =
    billingSnapshot?.planPrice ??
    plan?.price ??
    shop?.plan?.price ??
    null;
  const planValue = planName
    ? planPrice
      ? `${planName} · ${formatCurrencyValue(planPrice, baseCurrency)} / ${I18n.t("billing.month")}`
      : planName
    : placeholderValue;

  const cappedAmount = billingSnapshot?.cappedAmount;
  const cappedUsed = billingSnapshot?.cappedUsed;
  const cappedRemaining = billingSnapshot?.cappedBalanceRemaining;
  const cappedUsedPct =
    cappedAmount && cappedAmount > 0 && cappedUsed
      ? Math.min(
          100,
          Math.round((Number(cappedUsed) / Number(cappedAmount)) * 100)
        )
      : null;

  const cappedHelper =
    cappedAmount && cappedRemaining !== undefined && cappedRemaining !== null
      ? I18n.t("billing.remaining_this_cycle", { amount: formatCurrencyValue(cappedRemaining, baseCurrency) || placeholderValue })
      : I18n.t("billing.set_in_shopify_billing");

  const usedHelper =
    cappedUsedPct !== null
      ? I18n.t("billing.pct_of_cap", { pct: cappedUsedPct })
      : I18n.t("billing.resets_every_cycle");

  const smsRate = billingSnapshot?.smsRate;
  const whatsappRate = billingSnapshot?.whatsappRate;
  const whatsappMarketingRate = billingSnapshot?.whatsappMarketingRate;
  const bspWhatsappRate = billingSnapshot?.bspWhatsappRate;

  const smsRateDisplay = smsRate
      ? `${formatCurrencyValue(smsRate, "USD")} / ${I18n.t("billing.sms_unit")}`
      : placeholderValue;
  const whatsappRateDisplay = whatsappRate
    ? `${formatCurrencyValue(whatsappRate, "USD")} / ${I18n.t("billing.conversation_unit")}`
    : placeholderValue;
  const whatsappMarketingRateDisplay = whatsappMarketingRate
    ? `${formatCurrencyValue(whatsappMarketingRate, "USD")} / ${I18n.t("billing.message_unit")}`
    : placeholderValue;
  const bspWhatsappRateDisplay = bspWhatsappRate != null
    ? `${formatCurrencyValue(bspWhatsappRate, "USD")} / ${I18n.t("billing.message_unit")}`
    : placeholderValue;

  const partialFee = billingSnapshot?.partialPaymentFee;
  const partialFeeDisplay = partialFee
    ? I18n.t("billing.partial_fee_per_order", { pct: formatPercent(partialFee) })
    : placeholderValue;
  const partialHelper =
    billingSnapshot?.partialFeeSource === "custom"
      ? I18n.t("billing.custom_override")
      : I18n.t("billing.default_plan_rate", { plan: planName || I18n.t("billing.plan") });

  const formatDate = useCallback(
    (value) => {
      if (!value) return null;
      try {
        return dateFormatter.format(new Date(value));
      } catch (error) {
        console.warn("[Billing] Failed to format date", value, error);
        return null;
      }
    },
    [dateFormatter]
  );

  const getSummaryMetric = useCallback(
    (path) => {
      if (!usageSummary) return null;
      return path.reduce(
        (acc, key) =>
          acc && acc[key] !== undefined && acc[key] !== null ? acc[key] : null,
        usageSummary
      );
    },
    [usageSummary]
  );

  const renderUsageBadge = useCallback(
    (path, unitLabel = "SMS") => {
      if (usageLoading) {
        return (
          <Badge tone="subdued" size="medium">
            {I18n.t("billing.loading")}
          </Badge>
        );
      }

      const metric = getSummaryMetric(path);

      if (!metric) {
        return (
          <Badge tone="subdued" size="medium">
            {placeholderValue}
          </Badge>
        );
      }

      const amountDisplay =
        metric.amount !== null && metric.amount !== undefined
          ? formatCurrencyValue(metric.amount, baseCurrency, {
              minimumFractionDigits: 4,
              maximumFractionDigits: 4,
            })
          : placeholderValue;

      const countValue = metric.count || 0;
      const countDisplay = `${numberFormatter.format(countValue)} ${unitLabel}`;

      return (
        <Badge tone="info" size="medium">
          {countDisplay} • {amountDisplay}
        </Badge>
      );
    },
    [
      usageLoading,
      getSummaryMetric,
      formatCurrencyValue,
      baseCurrency,
      numberFormatter,
    ]
  );

  const breakdownOptions = getBreakdownOptions();
  const smsUsageDefinitions = getSmsUsageDefinitions();
  const whatsappUsageDefinitions = getWhatsappUsageDefinitions();

  const smsTimeframeLabel =
    usageSummary?.timeframe?.label || I18n.t("billing.last_n_days", { n: selectedRange });

  const formatDateRange = useCallback(
    (start, end) => {
      const startText = formatDate(start);
      const endText = formatDate(end);
      if (startText && endText) {
        return `${startText} - ${endText}`;
      }
      return startText || endText || placeholderValue;
    },
    [formatDate, placeholderValue]
  );

  const overviewItems = [
    {
      id: "plan",
      label: I18n.t("billing.current_plan"),
      helper:
        billingSnapshot?.planPriceSource === "shopify"
          ? I18n.t("billing.synced_from_subscription")
          : I18n.t("billing.plan_list_price", {
              defaultValue: "Plan list price — no active Shopify charge found",
            }),
      value: planValue,
    },
    {
      id: "cappedAmount",
      label: I18n.t("billing.capped_amount"),
      helper: cappedHelper,
      value:
        formatCurrencyValue(cappedAmount, baseCurrency) || placeholderValue,
    },
    {
      id: "usedCappedAmount",
      label: I18n.t("billing.used_capped_amount"),
      helper: usedHelper,
      value:
        formatCurrencyValue(cappedUsed, baseCurrency) || placeholderValue,
    },
    {
      id: "smsRate",
      label: I18n.t("billing.current_sms_rate"),
      helper: I18n.t("billing.per_message_cost"),
      value: smsRateDisplay,
    },
    {
      id: "whatsappRate",
      label: I18n.t("billing.current_whatsapp_rate"),
      helper: I18n.t("billing.per_conversation_cost"),
      value: whatsappRateDisplay,
    },
    {
      id: "whatsappMarketingRate",
      label: I18n.t("billing.current_whatsapp_marketing_rate"),
      helper: I18n.t("billing.per_marketing_message_cost"),
      value: whatsappMarketingRateDisplay,
    },
    {
      id: "bspWhatsappRate",
      label: I18n.t("billing.current_bsp_whatsapp_rate"),
      helper: I18n.t("billing.per_bsp_message_cost"),
      value: bspWhatsappRateDisplay,
    },
    {
      id: "partialFees",
      label: I18n.t("billing.partial_fees_label"),
      helper: partialHelper,
      badge: I18n.t("billing.partial_only"),
      value: partialFeeDisplay,
    },
  ];

  const formatAmountCell = useCallback(
    (value) => {
      if (value === null || value === undefined) {
        return placeholderValue;
      }

      return (
        formatCurrencyValue(value, baseCurrency, {
          minimumFractionDigits: value < 1 ? 4 : 2,
          maximumFractionDigits: value < 1 ? 4 : 2,
        }) || placeholderValue
      );
    },
    [formatCurrencyValue, baseCurrency]
  );

  const placeholderBreakdownRows = useMemo(() => {
    const offsets = rangeOffsets[selectedRange] || rangeOffsets["30"];
    return offsets.map((offset) => {
      const targetDate = new Date();
      targetDate.setDate(targetDate.getDate() - offset);
      const formattedDate = targetDate.toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
      });
      return [
        formattedDate,
        placeholderValue,
        placeholderValue,
        placeholderValue,
        placeholderValue,
      ];
    });
  }, [selectedRange]);

  const breakdownRows = useMemo(() => {
    if (!usageSummary?.breakdown?.length) {
      return placeholderBreakdownRows;
    }

    return usageSummary.breakdown.map((bucket) => [
      formatDateRange(bucket.range?.start, bucket.range?.end),
      formatAmountCell(bucket.sms?.amount),
      formatAmountCell(bucket.whatsapp?.amount),
      formatAmountCell(bucket.transaction?.amount),
      formatAmountCell(bucket.total?.amount),
    ]);
  }, [usageSummary, formatAmountCell, placeholderBreakdownRows, formatDateRange]);

  const breakdownTotals = useMemo(() => {
    if (!usageSummary?.breakdown?.length) {
      return [
        I18n.t("billing.totals"),
        placeholderValue,
        placeholderValue,
        placeholderValue,
        placeholderValue,
      ];
    }

    const sums = usageSummary.breakdown.reduce(
      (acc, bucket) => {
        acc.sms += bucket.sms?.amount || 0;
        acc.whatsapp += bucket.whatsapp?.amount || 0;
        acc.transaction += bucket.transaction?.amount || 0;
        acc.total += bucket.total?.amount || 0;
        return acc;
      },
      { sms: 0, whatsapp: 0, transaction: 0, total: 0 }
    );

    return [
      I18n.t("billing.totals"),
      formatAmountCell(sums.sms),
      formatAmountCell(sums.whatsapp),
      formatAmountCell(sums.transaction),
      formatAmountCell(sums.total),
    ];
  }, [usageSummary, formatAmountCell]);

  const toggleSmsCharges = useCallback(
    () => setSmsChargesOpen((prev) => !prev),
    []
  );

  const toggleWhatsappCharges = useCallback(
    () => setWhatsappChargesOpen((prev) => !prev),
    []
  );

  const exportBreakdown = useCallback(() => {
    if (!usageSummary?.breakdown?.length) {
      console.warn("[Billing] No data to export");
      return;
    }

    // Calculate totals
    const sums = usageSummary.breakdown.reduce(
      (acc, bucket) => {
        acc.sms += bucket.sms?.amount || 0;
        acc.whatsapp += bucket.whatsapp?.amount || 0;
        acc.transaction += bucket.transaction?.amount || 0;
        acc.total += bucket.total?.amount || 0;
        return acc;
      },
      { sms: 0, whatsapp: 0, transaction: 0, total: 0 }
    );

    // Prepare CSV data
    const headers = [
      "Date Range",
      "SMS Charges ($)",
      "WhatsApp Charges ($)",
      "Transaction Fees ($)",
      "Total ($)",
    ];

    const rows = usageSummary.breakdown.map((bucket) => [
      bucket.label || "",
      (bucket.sms?.amount || 0).toFixed(4),
      (bucket.whatsapp?.amount || 0).toFixed(4),
      (bucket.transaction?.amount || 0).toFixed(4),
      (bucket.total?.amount || 0).toFixed(4),
    ]);

    // Add totals row
    rows.push([
      "Totals",
      sums.sms.toFixed(4),
      sums.whatsapp.toFixed(4),
      sums.transaction.toFixed(4),
      sums.total.toFixed(4),
    ]);

    // Convert to CSV
    const csvContent = [
      headers.join(","),
      ...rows.map((row) => row.map((cell) => `"${cell}"`).join(",")),
    ].join("\n");

    // Create download link
    const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
    const link = document.createElement("a");
    const url = URL.createObjectURL(blob);
    
    const timeframeLabel = usageSummary?.timeframe?.label || 
      (useDateRange 
        ? `${startDate}_to_${endDate}`
        : `last_${selectedRange}_days`);
    
    link.setAttribute("href", url);
    link.setAttribute("download", `billing_breakdown_${timeframeLabel.replace(/[^a-zA-Z0-9]/g, "_")}.csv`);
    link.style.visibility = "hidden";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }, [usageSummary, useDateRange, startDate, endDate, selectedRange]);

  // Loading skeleton – matches Billing: date range card + overview key-value grid + content cards
  if (usageLoading && !usageSummary) {
    return (
      <SkeletonPage title={I18n.t("billing.title")} primaryAction>
        <Layout>
          <Layout.Section variant="twoThirds">
            <BlockStack gap="400">
              <Card padding="600">
                <BlockStack gap="300">
                  <SkeletonDisplayText size="small" />
                  <SkeletonBodyText lines={1} />
                  <InlineStack gap="200">
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                  </InlineStack>
                </BlockStack>
              </Card>
              <Card padding="600">
                <BlockStack gap="400">
                  <BlockStack gap="150">
                    <SkeletonDisplayText size="small" />
                    <SkeletonBodyText lines={1} />
                  </BlockStack>
                  <InlineGrid columns={{ xs: 1, sm: 2, lg: 3 }} gap="300">
                    {[1, 2, 3, 4, 5, 6].map((i) => (
                      <Box key={i} padding="300" background="bg-surface-secondary" borderRadius="200">
                        <BlockStack gap="100">
                          <SkeletonBodyText lines={1} />
                          <SkeletonDisplayText size="small" />
                        </BlockStack>
                      </Box>
                    ))}
                  </InlineGrid>
                </BlockStack>
              </Card>
              <Card padding="600">
                <BlockStack gap="200">
                  <SkeletonDisplayText size="small" />
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                </BlockStack>
              </Card>
            </BlockStack>
          </Layout.Section>
        </Layout>
      </SkeletonPage>
    );
  }

  return (
    <Page
      title={I18n.t("billing.title")}
      subtitle={I18n.t("billing.subtitle")}
      fullWidth={true}
    >
      <Layout>
        <Layout.Section variant="twoThirds">
          <BlockStack gap="400">
            <FeatureCallout
              illustration="payments"
              title={I18n.t("billing.title")}
              description={I18n.t("billing.subtitle")}
              docsUrl="https://codking.tech/documentation/"
              actions={
                <Button onClick={() => navigateTo("/subscription")}>
                  {I18n.t("billing.manage_subscription")}
                </Button>
              }
              showChat
            />

            {/* COD Form order usage + overage line (nothing for shops without the module) */}
            <BillingUsageRows />

            {/* Date Range Selector */}
            <Card padding="600">
              <BlockStack gap="300">
                <Text variant="headingMd" as="h2">
                  {I18n.t("billing.select_date_range")}
                </Text>
                <Text variant="bodySm" tone="subdued">
                  {I18n.t("billing.select_date_range_desc")}
                </Text>
                <InlineStack gap="200" blockAlign="end">
                  <Box minWidth="200px">
                    <Select
                      label={I18n.t("billing.quick_range")}
                      options={[
                        { label: I18n.t("billing.custom_range"), value: "custom" },
                        ...breakdownOptions,
                      ]}
                      value={useDateRange ? "custom" : selectedRange}
                      onChange={(value) => {
                        if (value === "custom") {
                          setUseDateRange(true);
                        } else {
                          setUseDateRange(false);
                          setSelectedRange(value);
                        }
                      }}
                    />
                  </Box>
                  {useDateRange && (
                    <>
                      <Box minWidth="180px">
                        <BlockStack gap="050">
                          <Text variant="bodySm" as="label" htmlFor="start-date" fontWeight="medium">
                            {I18n.t("billing.start_date")}
                          </Text>
                          <TextField
                            id="start-date"
                            label={I18n.t("billing.start_date")}
                            labelHidden
                            type="date"
                            value={startDate}
                            onChange={setStartDate}
                            max={endDate}
                            autoComplete="off"
                          />
                        </BlockStack>
                      </Box>
                      <Box minWidth="180px">
                        <BlockStack gap="050">
                          <Text variant="bodySm" as="label" htmlFor="end-date" fontWeight="medium">
                            {I18n.t("billing.end_date")}
                          </Text>
                          <TextField
                            id="end-date"
                            label={I18n.t("billing.end_date")}
                            labelHidden
                            type="date"
                            value={endDate}
                            onChange={setEndDate}
                            min={startDate}
                            max={new Date().toISOString().split("T")[0]}
                            autoComplete="off"
                          />
                        </BlockStack>
                      </Box>
                    </>
                  )}
                  <Button
                    variant="primary"
                    onClick={applyDateFilter}
                    loading={usageLoading}
                    disabled={isApplyDisabled}
                  >
                    {I18n.t("billing.apply", { defaultValue: "Apply" })}
                  </Button>
                </InlineStack>
              </BlockStack>
            </Card>

            <Card padding="600">
              <BlockStack gap="400">
                <BlockStack gap="150">
                  <Text variant="headingMd" as="h2">
                    {I18n.t("billing.subscription_overview")}
                  </Text>
                  <Text variant="bodySm" tone="subdued">
                    {I18n.t("billing.subscription_overview_desc")}
                  </Text>
                </BlockStack>

                <InlineGrid columns={{ xs: 1, sm: 2, lg: 3 }} gap="300">
                  {overviewItems.map((item) => (
                    <Box
                      key={item.id}
                      padding="300"
                      background="bg-surface-secondary"
                      borderRadius="200"
                    >
                      <BlockStack gap="100">
                        <InlineStack gap="150" blockAlign="center">
                          <Text variant="bodySm" tone="subdued">
                            {item.label}
                          </Text>
                          {item.badge && (
                            <Badge tone="attention" size="small">
                              {item.badge}
                            </Badge>
                          )}
                        </InlineStack>
                        <Text variant="headingMd">
                          {item.value || placeholderValue}
                        </Text>
                        <Text variant="bodySm" tone="subdued">
                          {item.helper}
                        </Text>
                      </BlockStack>
                    </Box>
                  ))}
                </InlineGrid>
              </BlockStack>
            </Card>

            <Card padding="600">
              <BlockStack gap="300">
                <BlockStack gap="100">
                  <Text variant="headingMd" as="h2">
                    {I18n.t("billing.referral_partner_title")}
                  </Text>
                  <Text variant="bodySm" tone="subdued">
                    {I18n.t("billing.referral_partner_desc")}
                  </Text>
                </BlockStack>
                {referralBanner && (
                  <Banner
                    tone={referralBanner.tone}
                    onDismiss={() => setReferralBanner(null)}
                  >
                    {referralBanner.message}
                  </Banner>
                )}
                {referralStatusLoading ? (
                  <Text variant="bodySm" tone="subdued">
                    {I18n.t("billing.loading")}
                  </Text>
                ) : referralStatus?.linked ? (
                  referralStatus.approved ? (
                    <BlockStack gap="200">
                      <Banner tone="success">
                        {I18n.t("billing.referral_partner_linked", {
                          name: referralStatus.partnerName || "—",
                        })}
                      </Banner>
                      <InlineStack>
                        <Button
                          tone="critical"
                          variant="plain"
                          loading={referralUnlinking}
                          onClick={unlinkReferralCode}
                        >
                          {I18n.t("billing.referral_unlink")}
                        </Button>
                      </InlineStack>
                    </BlockStack>
                  ) : (
                    <BlockStack gap="200">
                      <Banner tone="warning">
                        {I18n.t("billing.referral_partner_pending")}
                      </Banner>
                      <InlineStack>
                        <Button
                          tone="critical"
                          variant="plain"
                          loading={referralUnlinking}
                          onClick={unlinkReferralCode}
                        >
                          {I18n.t("billing.referral_unlink")}
                        </Button>
                      </InlineStack>
                    </BlockStack>
                  )
                ) : (
                  <InlineStack gap="200" blockAlign="end" wrap>
                    <Box minWidth="220px" maxWidth="100%">
                      <TextField
                        label={I18n.t("billing.referral_code_label")}
                        value={referralCode}
                        onChange={setReferralCode}
                        placeholder={I18n.t("billing.referral_code_placeholder")}
                        autoComplete="off"
                      />
                    </Box>
                    <Button
                      variant="primary"
                      loading={referralApplying}
                      onClick={applyReferralCode}
                      disabled={!referralCode.trim()}
                    >
                      {referralApplying
                        ? I18n.t("billing.referral_applying")
                        : I18n.t("billing.referral_apply")}
                    </Button>
                  </InlineStack>
                )}
              </BlockStack>
            </Card>

            <Card padding="600">
              <BlockStack gap="300">
                <InlineStack align="space-between" blockAlign="center">
                  <InlineStack align="space-between" blockAlign="center">
                    <BlockStack gap="100">
                      <Text variant="headingMd" as="h2">
                        {I18n.t("billing.breakdown_title")}
                      </Text>
                      <Text variant="bodySm" tone="subdued">
                        {I18n.t("billing.breakdown_desc")}
                      </Text>
                    </BlockStack>
                    <Button variant="tertiary" onClick={exportBreakdown}>
                      {I18n.t("billing.export_breakdown")}
                    </Button>
                  </InlineStack>
                </InlineStack>

                <DataTable
                  columnContentTypes={[
                    "text",
                    "text",
                    "text",
                    "text",
                    "text",
                  ]}
                  headings={[
                    I18n.t("billing.date_range"),
                    I18n.t("billing.sms_charges"),
                    I18n.t("billing.whatsapp_charges"),
                    I18n.t("billing.transaction_fees"),
                    I18n.t("billing.total"),
                  ]}
                  rows={breakdownRows}
                totals={breakdownTotals}
                  showTotalsInFooter
                />

                <Text variant="bodySm" tone="subdued">
                  {I18n.t("billing.usage_data_note")}
                </Text>
              </BlockStack>
            </Card>

            <Card padding="600">
              <BlockStack gap="300">
                <InlineStack align="space-between" blockAlign="center">
                  <BlockStack gap="050">
                    <Text variant="headingMd" as="h2">
                      {I18n.t("billing.sms_charges")}
                    </Text>
                    <Text variant="bodySm" tone="subdued">
                      {I18n.t("billing.sms_charges_desc")}
                    </Text>
                    <Text variant="bodySm" tone="subdued">
                      {usageSummary
                        ? I18n.t("billing.actual_charges", { period: usageSummary.timeframe?.label || smsTimeframeLabel })
                        : I18n.t("billing.pulling_data")}
                    </Text>
                  </BlockStack>
                  <Button
                    icon={smsChargesOpen ? ChevronUpMinor : ChevronDownMinor}
                    variant="tertiary"
                    onClick={toggleSmsCharges}
                    accessibilityLabel={
                      smsChargesOpen
                        ? I18n.t("billing.collapse_sms")
                        : I18n.t("billing.expand_sms")
                    }
                  >
                    {smsChargesOpen ? I18n.t("billing.hide") : I18n.t("billing.show")}
                  </Button>
                </InlineStack>

                {/* Total SMS Charges */}
                {usageSummary?.totals?.sms && (
                  <Box
                    padding="300"
                    background="bg-surface-secondary"
                    borderRadius="200"
                  >
                    <InlineStack align="space-between" blockAlign="center">
                      <Text variant="bodyMd" fontWeight="semibold">
                        {I18n.t("billing.total_sms_charges")}
                      </Text>
                      <Badge tone="info" size="medium">
                        {I18n.t("billing_usage.sms_usage_badge", {
                          count: numberFormatter.format(
                            usageSummary.totals.sms.count
                          ),
                          amount: formatCurrencyValue(
                            usageSummary.totals.sms.amount,
                            baseCurrency,
                            {
                              minimumFractionDigits: 4,
                              maximumFractionDigits: 4,
                            }
                          ),
                        })}
                      </Badge>
                    </InlineStack>
                  </Box>
                )}

                <Collapsible open={smsChargesOpen} id="sms-charges-collapsible">
                  <Divider />
                  <BlockStack gap="300" paddingBlockStart="300">
                    {smsUsageDefinitions.map((item) => (
                      <Box
                        key={item.id}
                        padding="300"
                        background="bg-surface-neutral-subdued"
                        borderRadius="200"
                      >
                        <InlineStack align="space-between" blockAlign="center">
                          <BlockStack gap="050">
                            <Text variant="bodyMd" fontWeight="semibold">
                              {item.title}
                            </Text>
                            <Text variant="bodySm" tone="subdued">
                              {item.description}
                            </Text>
                          </BlockStack>
                          {renderUsageBadge(item.summaryPath, "SMS")}
                        </InlineStack>
                      </Box>
                    ))}
                  </BlockStack>
                </Collapsible>
              </BlockStack>
            </Card>

            <Card padding="600">
              <BlockStack gap="300">
                <InlineStack align="space-between" blockAlign="center">
                  <BlockStack gap="050">
                    <Text variant="headingMd" as="h2">
                      {I18n.t("billing.whatsapp_charges")}
                    </Text>
                    <Text variant="bodySm" tone="subdued">
                      {I18n.t("billing.whatsapp_charges_desc")}
                    </Text>
                    <Text variant="bodySm" tone="subdued">
                      {usageSummary
                        ? I18n.t("billing.actual_charges", { period: usageSummary.timeframe?.label || smsTimeframeLabel })
                        : I18n.t("billing.pulling_data")}
                    </Text>
                  </BlockStack>
                  <Button
                    icon={whatsappChargesOpen ? ChevronUpMinor : ChevronDownMinor}
                    variant="tertiary"
                    onClick={toggleWhatsappCharges}
                    accessibilityLabel={
                      whatsappChargesOpen
                        ? I18n.t("billing.collapse_whatsapp")
                        : I18n.t("billing.expand_whatsapp")
                    }
                  >
                    {whatsappChargesOpen ? I18n.t("billing.hide") : I18n.t("billing.show")}
                  </Button>
                </InlineStack>

                {/* Total WhatsApp Charges */}
                {usageSummary?.totals?.whatsapp && (
                  <Box
                    padding="300"
                    background="bg-surface-secondary"
                    borderRadius="200"
                  >
                    <InlineStack align="space-between" blockAlign="center">
                      <Text variant="bodyMd" fontWeight="semibold">
                        {I18n.t("billing.total_whatsapp_charges")}
                      </Text>
                      <Badge tone="info" size="medium">
                        {I18n.t("billing_usage.whatsapp_usage_badge", {
                          count: numberFormatter.format(
                            usageSummary.totals.whatsapp.count
                          ),
                          amount: formatCurrencyValue(
                            usageSummary.totals.whatsapp.amount,
                            baseCurrency,
                            {
                              minimumFractionDigits: 4,
                              maximumFractionDigits: 4,
                            }
                          ),
                        })}
                      </Badge>
                    </InlineStack>
                  </Box>
                )}

                <Collapsible open={whatsappChargesOpen} id="whatsapp-charges-collapsible">
                  <Divider />
                  <BlockStack gap="300" paddingBlockStart="300">
                    {whatsappUsageDefinitions.map((item) => (
                      <Box
                        key={item.id}
                        padding="300"
                        background="bg-surface-neutral-subdued"
                        borderRadius="200"
                      >
                        <InlineStack align="space-between" blockAlign="center">
                          <BlockStack gap="050">
                            <Text variant="bodyMd" fontWeight="semibold">
                              {item.title}
                            </Text>
                            <Text variant="bodySm" tone="subdued">
                              {item.description}
                            </Text>
                          </BlockStack>
                          {renderUsageBadge(item.summaryPath, "conversations")}
                        </InlineStack>
                      </Box>
                    ))}
                  </BlockStack>
                </Collapsible>
              </BlockStack>
            </Card>

            <Card padding="600">
              <BlockStack gap="300">
                <InlineStack gap="200" blockAlign="center">
                  <Text variant="headingMd" as="h2">
                    {I18n.t("billing.transaction_fees")}
                  </Text>
                  <Badge tone="attention" size="small">
                    {I18n.t("billing.partial_payment_orders")}
                  </Badge>
                </InlineStack>
                <Text variant="bodySm" tone="subdued">
                  {I18n.t("billing.transaction_fees_desc")}
                </Text>
                <Text variant="bodySm" tone="subdued">
                  {usageSummary
                    ? I18n.t("billing.actual_charges", { period: usageSummary.timeframe?.label || smsTimeframeLabel })
                    : I18n.t("billing.pulling_data")}
                </Text>

                {/* Total Transaction Fees */}
                {usageSummary?.totals?.transaction && (
                  <Box
                    padding="300"
                    background="bg-surface-secondary"
                    borderRadius="200"
                  >
                    <InlineStack align="space-between" blockAlign="center">
                      <Text variant="bodyMd" fontWeight="semibold">
                        {I18n.t("billing.total_transaction_fees")}
                      </Text>
                      <Badge tone="info" size="medium">
                        {I18n.t("billing_usage.transaction_usage_badge", {
                          count: numberFormatter.format(
                            usageSummary.totals.transaction.count
                          ),
                          amount: formatCurrencyValue(
                            usageSummary.totals.transaction.amount,
                            baseCurrency,
                            {
                              minimumFractionDigits: 4,
                              maximumFractionDigits: 4,
                            }
                          ),
                        })}
                      </Badge>
                    </InlineStack>
                  </Box>
                )}

                <Box
                  padding="300"
                  background="bg-surface-neutral-subdued"
                  borderRadius="200"
                >
                  <InlineStack align="space-between" blockAlign="center">
                    <BlockStack gap="050">
                      <Text variant="bodyMd" fontWeight="semibold">
                        {I18n.t("billing.current_fee_rate")}
                      </Text>
                      <Text variant="bodySm" tone="subdued">
                        {partialHelper}
                      </Text>
                    </BlockStack>
                    <Badge tone="subdued" size="medium">
                      {partialFeeDisplay}
                    </Badge>
                  </InlineStack>
                </Box>
                <InlineStack gap="200">
                  <Button onClick={() => navigateTo("/features/partial-payment")}>
                    {I18n.t("billing.review_partial_setup")}
                  </Button>
                  <Button variant="tertiary" onClick={() => navigateTo("/usage-analytics")}>
                    {I18n.t("billing.see_usage_analytics")}
                  </Button>
                </InlineStack>
              </BlockStack>
            </Card>
          </BlockStack>
        </Layout.Section>

        <Layout.Section variant="oneThird">
          <BlockStack gap="400">
            {/* <MediaCard
              title="Video: How pricing works with COD King"
              primaryAction={{
                content: "Watch walkthrough",
                onAction: () =>
                  window.open(
                    "https://www.youtube.com/watch?v=I22U3fj6vKo",
                    "_blank",
                    "noopener"
                  ),
              }}
              description="Understand caps, SMS/WhatsApp rates, and pay-as-you-grow billing in under two minutes."
            >
              <VideoThumbnail
                videoLength={110}
                thumbnailUrl="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/cod-king-video-thumb.png?v=1731851789"
                onClick={() =>
                  window.open(
                    "https://www.youtube.com/watch?v=I22U3fj6vKo",
                    "_blank",
                    "noopener"
                  )
                }
              />
            </MediaCard> */}

            <Card padding="600">
              <BlockStack gap="200">
                <Text variant="headingMd" as="h3">
                  {I18n.t("billing.article_title")}
                </Text>
                <Text variant="bodySm" tone="subdued">
                  {I18n.t("billing.article_desc")}
                </Text>
                <InlineStack gap="150">
                  <Button
                    icon={ExternalSmallMinor}
                    url="https://codking.tech/how-pricing-works-in-cod-king/"
                    target="_blank"
                    external
                    accessibilityLabel={I18n.t("billing.read_pricing_article_in_a_new")}
                  >
                    {I18n.t("billing.read_article")}
                  </Button>
                  <Link
                    url="https://codking.tech/how-pricing-works-in-cod-king/"
                    target="_blank"
                    external
                    monochrome
                  >
                    {I18n.t("billing.copy_link")}
                  </Link>
                </InlineStack>
                <Box paddingBlockStart="200" borderBlockStartWidth="025" borderColor="border">
                  <BlockStack gap="150">
                    <Text variant="bodyMd" fontWeight="semibold">
                      {I18n.t("billing.usage_rates_page_title")}
                    </Text>
                    <Text variant="bodySm" tone="subdued">
                      {I18n.t("billing.usage_rates_page_desc")}
                    </Text>
                    <InlineStack>
                      <Button
                        icon={ExternalSmallMinor}
                        url={`${window.location.origin}/pricing`}
                        target="_blank"
                        external
                        accessibilityLabel={I18n.t("billing.usage_rates_page_a11y")}
                      >
                        {I18n.t("billing.usage_rates_page_cta")}
                      </Button>
                    </InlineStack>
                  </BlockStack>
                </Box>
              </BlockStack>
            </Card>
          </BlockStack>
        </Layout.Section>
      </Layout>
    </Page>
  );
};

export default Billing;

