<script>
  import { onMount, onDestroy, tick, createEventDispatcher } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { get } from "svelte/store";
  const dispatch = createEventDispatcher();
  import { appStore, actions } from "../../stores/buttonManager.js";
  import otpStore, { otpStoreActions } from "../../stores/otpStore.js";
  import { toast } from "../../utils/toast.js";
  import {
    convertFloatToInt,
    initializeCartAndRules,
    handleRuleSelection,
    calculateRulePrice,
    generateRuleDescription,
    hasRuleDiscount,
    handlePaymentSubmit,
    rulesNeedCartItemCount,
  } from "../../utils/paymentOptionsUtils.js";
  import {
    getDescBundle,
    getPriceBundle,
  } from "../../utils/bundlePaymentUtils.js";
  import {
    getSessionValue,
    getCurrentStep,
    removeSessionValue,
    getStorefrontCartId,
    buildBuyerIdentityPayload,
  } from "../../utilities/otpUtils.js";
  import { setSessionValue, isOptimizedBuyNowEnabled } from "../../services/sessionService.js";
  import {
    formatCurrency as formatCurrencyHelper,
    mapCartToOrderSummary,
    getShopDomain,
    isTaxIncludedWithProductAny,
  } from "../../utils/helpers.js";
  import { calculateTax } from "../../services/api.js";
  import { createTranslator, interpolate, uiText } from "../../utils/uiCustomization.js";
  import { handlePartialPaymentSubmitBundle } from "../../utils/partialPaymentUtils.js";
  import {
    completeCodOrder,
    initiateRazorpayPayment,
    verifyRazorpayAndCreateOrder,
    toRupees,
    resolveShippingAddress,
    getBuyerIdentity,
  } from "../../services/orderService.js";
  import { updateBuyerIdentity } from "../../services/cartService.js";
  import ErrorDisplay from "../shared/ErrorDisplay.svelte";
  import PromoBanner from "../shared/PromoBanner.svelte";
  import PaymentOptionSkeleton from "../shared/PaymentOptionSkeleton.svelte";
  import RazorpayEmbed from "../shared/RazorpayEmbed.svelte";
  import BottomSlider from "../shared/BottomSlider.svelte";
  import Sheet from "../ui/Sheet.svelte";
  import Card from "../ui/Card.svelte";
  import { codOrderFlowStore } from "../../stores/codOrderFlowStore.js";
  import "../../styles/components/sections/PaymentOptionsSection.css";
  import "../../styles/components/sections/PaymentOptionsSection.mobile.css";

  let ruleSets = [];
  let selectedRule = null;
  let error = "";
  let cartTotal = 0;
  let isFullPercentage = true;
  let isCOD = true;
  export let isPartialLoading = false;
  $: isLoaderLoading = $otpStore.isLoaderLoading;

  let settings = null;
  let currencyCode = "INR";
  let unsubscribeAppStore;
  let hasInitialized = false;
  let didAutoSelectFirstRule = false;
  let isInitializing = false;
  // Set when initialize() is asked to run mid-flight (e.g. address or email
  // changed while rules were loading) so the latest identity gets filtered.
  let reinitPending = false;
  // Guards the one-time re-filter once the authoritative cart replaces the
  // optimistic (scraped) one, so total-based rules reconcile to the real cart.
  let didReconcileRealCart = false;
  // Sliding window of recent initialize() calls — trips the runaway guard.
  let initCallTimestamps = [];
  let lastFilteredAddressId;
  let isCreatingOrder = false;
  let orderSuccessMessage = "";
  let orderError = "";
  /** True when the shop has partial rules but none qualify for the current cart (filters). */
  let noEligiblePartialRules = false;
  let isProcessingPayment = false;
  let showRazorpayEmbed = false;
  let razorpayEmbedOptions = null;
  let showCodConfirm = false;
  let codConfirmRule = null;
  $: otpState = $otpStore;
  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore || $appStore.settings);
  $: optimizedBuyNow = ($otpStore.settings, isOptimizedBuyNowEnabled());
  // PDP buy now paints a real (scraped) optimistic summary, so we show the real
  // payment cards there. Quick view / checkout have no optimistic data (pending),
  // so we keep the payment skeleton until the authoritative cart is ready.
  $: hasOptimisticSummaryData =
    otpState.isSummaryOptimistic &&
    (otpState.currentCartData?.items?.length || 0) > 0;
  // A rule with a cart item range can only be decided on the real cart.js
  // cart, so while any rule has one the payment cards wait for it — even on
  // optimized Buy Now, where they would otherwise render off the scraped cart.
  let needsCartItemCount = rulesNeedCartItemCount(getSessionValue("ruleSets"));
  $: waitingForRealCart =
    needsCartItemCount &&
    (!otpState.isCartReady || otpState.isSummaryOptimistic) &&
    !otpState.cartLoadFailed;
  $: showPaymentSkeleton =
    isLoaderLoading ||
    waitingForRealCart ||
    (optimizedBuyNow && !otpState.isCartReady && !hasOptimisticSummaryData);

  $: {
    const currentAddressId = $otpStore?.selectedAddress;
    if (
      hasInitialized &&
      currentAddressId !== undefined &&
      currentAddressId !== lastFilteredAddressId
    ) {
      lastFilteredAddressId = currentAddressId;
      initialize();
      fetchTaxForSelectedAddress();
    }
  }

  $: baseOrderSummary = mapCartToOrderSummary(
    otpState?.currentCartData,
    currencyCode || "INR",
  );
  $: calculatedTax = otpState?.calculatedTaxData || null;
  $: availableShippingRates = calculatedTax?.available_shipping_rates || [];
  $: selectedShippingHandle = otpState?.selectedShippingHandle || null;

  $: {
    if (availableShippingRates.length > 0 && !selectedShippingHandle) {
      const stored = getSessionValue("selected_shipping_handle");
      const defaultHandle =
        stored && availableShippingRates.some((r) => r.handle === stored)
          ? stored
          : availableShippingRates[0].handle;
      otpStore.setSelectedShippingHandle(defaultHandle);
      setSessionValue("selected_shipping_handle", defaultHandle);
    }
  }

  $: selectedShippingRate = availableShippingRates.find(
    (rate) => rate.handle === selectedShippingHandle,
  );
  $: shippingCost = (() => {
    const rawPrice = selectedShippingRate?.price || 0;
    return typeof rawPrice === "number" ? rawPrice : parseFloat(rawPrice) || 0;
  })();

  $: isPrefilledAddressEnabled = (() => {
    const s =
      settings || $settingsStore || $appStore.settings;
    return !!(
      s?.isPrefilledAddressEnabled === true ||
      s?.isPrefilledAddressEnabled === "true" ||
      s?.is_prefilled_address_enabled === true ||
      s?.is_prefilled_address_enabled === "true" ||
      s?.cod_form_enabled === true ||
      s?.cod_form_enabled === "true"
    );
  })();

  // Shipping is shown/used only when BOTH conditions are true: isPrefilledAddressEnabled AND preV2ShowShippingInfo
  $: showShippingInfo =
    isPrefilledAddressEnabled &&
    (settings?.pre_v2_show_shipping_info === true ||
      settings?.preV2ShowShippingInfo === true);
  $: effectiveSelectedShippingRate = showShippingInfo
    ? selectedShippingRate
    : null;
  // Opt-in (default off): fold a shipping charge into the per-option amounts and
  // show it as a badge. Independent of preV2ShowShippingInfo, which only controls
  // the shipping-method picker card.
  $: includeShippingInOptions = (() => {
    const s =
      settings || $settingsStore || $appStore.settings;
    const v =
      s?.includeShippingInPaymentOptions ??
      s?.include_shipping_in_payment_options;
    return v === true || String(v) === "true";
  })();
  // Purely the merchant-set amount on the rule. Unset (null) or 0 means this
  // option carries no shipping charge — Shopify's calculated rate is never
  // consulted here, so this works on redirect-only stores too.
  // Reactive on purpose: callers must recompute when the toggle flips, which a
  // plain const would not trigger.
  $: ruleShipping = ((enabled) => (rule) => {
    if (!enabled) return 0;
    const manual = parseFloat(rule?.shipping_charge ?? rule?.shippingCharge);
    return !isNaN(manual) && manual > 0 ? manual : 0;
  })(includeShippingInOptions);
  // Shipping for whichever rule is currently selected — drives the COD confirm
  // sheet, order creation and the Razorpay amount. Also the value written to the
  // order's shipping line, so what the popup showed is what gets charged.
  $: shippingAmount = (() => {
    const selectedRuleObj =
      selectedRule && ruleSets?.length
        ? ruleSets.find((r) => String(r.id) === String(selectedRule))
        : null;
    return selectedRuleObj ? ruleShipping(selectedRuleObj) : 0;
  })();
  // Any rule carrying a charge, so the each-block re-renders on change.
  $: ruleShippingSignature = (ruleSets || [])
    .map((r) => `${r.id}:${ruleShipping(r)}`)
    .join("|");
  // What every downstream money calculation should treat as shipping. The
  // legacy preV2ShowShippingInfo path is untouched for shops already on it.
  $: effectiveShippingCost = includeShippingInOptions
    ? shippingAmount
    : showShippingInfo
      ? Math.max(0, shippingCost)
      : 0;
  // Keep the bill summary in lockstep with the cards; guarded so writing to the
  // store cannot feed back into this statement and loop.
  let lastPushedShipping = null;
  $: if (shippingAmount !== lastPushedShipping) {
    lastPushedShipping = shippingAmount;
    otpStoreActions.setOptionShippingAmount(shippingAmount);
  }

  // Flag may exist only on session OR only on otp/app store — check every layer.
  $: taxInclusiveMerchant = isTaxIncludedWithProductAny(
    settings,
    $settingsStore,
    otpState?.settings,
    $appStore?.settings,
  );

  $: orderSummary = (() => {
    const s =
      settings ||
      $settingsStore ||
      $appStore?.settings ||
      otpState?.settings;
    const taxInclusive = taxInclusiveMerchant;
    const prefilledOn = !!(
      s?.isPrefilledAddressEnabled === true ||
      s?.isPrefilledAddressEnabled === "true" ||
      s?.is_prefilled_address_enabled === true ||
      s?.is_prefilled_address_enabled === "true" ||
      s?.cod_form_enabled === true ||
      s?.cod_form_enabled === "true"
    );
    if (!prefilledOn) {
      return {
        ...baseOrderSummary,
        taxAmount: 0,
        shippingCost: String(effectiveShippingCost),
      };
    }
    if (calculatedTax && calculatedTax.total_tax !== undefined) {
      const shipCostNum = effectiveShippingCost;
      return {
        ...baseOrderSummary,
        taxAmount: taxInclusive
          ? 0
          : typeof calculatedTax.total_tax === "number"
            ? calculatedTax.total_tax > 10000
              ? calculatedTax.total_tax / 100
              : calculatedTax.total_tax
            : baseOrderSummary.taxAmount,
        calculatedTaxData: calculatedTax,
        shippingCost: String(shipCostNum),
      };
    }
    const lastShipCost = effectiveShippingCost;
    return {
      ...baseOrderSummary,
      taxAmount: taxInclusive ? 0 : baseOrderSummary.taxAmount,
      shippingCost: String(lastShipCost),
    };
  })();
  $: computedTotal = (() => {
    const raw = (key) => {
      const v = orderSummary?.[key];
      return typeof v === "number" ? v : parseFloat(v) || 0;
    };
    const base = raw("total");
    const tax = raw("taxAmount");
    const ship = raw("shippingCost");
    const selectedRuleObj =
      selectedRule && ruleSets?.length
        ? ruleSets.find((r) => String(r.id) === String(selectedRule))
        : null;
    const codFee =
      selectedRuleObj?.amount_type === "cod" && selectedRuleObj.amount > 0
        ? parseFloat(selectedRuleObj.amount)
        : 0;

    return Math.round((base + codFee + tax + ship) * 100) / 100;
  })();

  // When cod_form_enabled is ON, show separate tax unless prices already include tax.
  // Otherwise use prefilled address + pre_v2_show_tax_info.
  $: showTaxInfo = (() => {
    if (taxInclusiveMerchant) return false;
    const s =
      settings ||
      $settingsStore ||
      $appStore?.settings ||
      otpState?.settings;
    const codFormEnabled =
      s?.cod_form_enabled === true ||
      s?.cod_form_enabled === "true" ||
      s?.codFormEnabled === true ||
      s?.codFormEnabled === "true";
    if (codFormEnabled) return true;
    return (
      isPrefilledAddressEnabled &&
      (s?.pre_v2_show_tax_info === true || s?.preV2ShowTaxInfo === true)
    );
  })();

  $: taxNote = taxInclusiveMerchant
    ? T("tax_included_note")
    : showTaxInfo
      ? ""
      : T("tax_excluded_note");

  $: hasDraftOrderTax =
    !taxInclusiveMerchant &&
    !!calculatedTax &&
    calculatedTax.total_tax > 0;

  $: taxRate = (() => {
    if (!hasDraftOrderTax) return 0;
    const taxLines = calculatedTax?.tax_lines;
    if (taxLines?.length > 0) {
      const sum = taxLines.reduce((s, l) => s + (parseFloat(l.rate) || 0), 0);
      if (sum > 0) return sum;
    }
    const tax = toRupees(calculatedTax.total_tax);
    const total = toRupees(orderSummary?.total || 0);
    if (tax > 0 && total > 0) {
      return Math.round((tax / total) * 10000) / 10000;
    }
    return 0;
  })();

  const getPayNowAmount = (rule) => {
    const cart = getSessionValue("shopify_cart") || getSessionValue("cart");
    const totalAfterDiscount = cart?.total_price
      ? (cart.total_price || 0) / 100
      : toRupees(orderSummary?.total || 0);
    const ruleAmount = parseFloat(rule.amount) || 0;

    let payNow = 0;
    if (rule.amount_type === "cod") {
      payNow = totalAfterDiscount;
    } else if (rule.amount_type === "percentage" && rule.amount === "100.0") {
      payNow = totalAfterDiscount;
    } else if (rule.amount_type === "fixed") {
      payNow = Math.min(ruleAmount, totalAfterDiscount);
    } else if (rule.amount_type === "percentage") {
      payNow = (totalAfterDiscount * ruleAmount) / 100;
    }
    return { payNow, totalAfterDiscount };
  };

  const getRuleTax = (rule) => {
    if (!taxRate || !showTaxInfo) return 0;
    const { payNow } = getPayNowAmount(rule);
    return Math.floor(payNow * taxRate * 100) / 100;
  };

  const getRemainingTax = (rule) => {
    if (!taxRate || !showTaxInfo) return 0;
    const { payNow, totalAfterDiscount } = getPayNowAmount(rule);
    const remaining = Math.max(0, totalAfterDiscount - payNow);
    return Math.floor(remaining * taxRate * 100) / 100;
  };

  /**
   * Ensure Shopify cart buyer identity is fully synced (email, phone, and
   * delivery address) when we skip the address step and land directly on
   * the payment screen. Uses the same payload as AddressSelection.
   * Only runs when isPrefilledAddressEnabled or cod_form_enabled is true.
   */
  async function ensureBuyerIdentitySyncedWithCart() {
    if (!isPrefilledAddressEnabled) return;
    try {
      const state = get(otpStore);
      const cartData = state.currentCartData || getSessionValue("shopify_cart");
      const cartToken = cartData?.token;
      if (!cartToken) return;

      const cartId = getStorefrontCartId(cartToken);
      if (!cartId) return;

      const buyerIdentity = getBuyerIdentity(state);
      if (!buyerIdentity?.email && !buyerIdentity?.phone) return;

      const resolvedAddress = resolveShippingAddress(state, cartData);
      const phone = buyerIdentity.phone || "";
      const email = buyerIdentity.email || null;

      let payload;
      if (resolvedAddress) {
        const selected = {
          first_name:
            resolvedAddress.first_name || resolvedAddress.firstName || "",
          last_name:
            resolvedAddress.last_name || resolvedAddress.lastName || "",
          address1: resolvedAddress.address1 || resolvedAddress.address_1 || "",
          address2: resolvedAddress.address2 || resolvedAddress.address_2 || "",
          city: resolvedAddress.city || "",
          state: resolvedAddress.province || resolvedAddress.state || "",
          zip: resolvedAddress.zip || resolvedAddress.postal_code || "",
        };
        payload = buildBuyerIdentityPayload(selected, phone, email);
      } else {
        payload = {
          email,
          phone: phone || null,
          countryCode: "IN",
          deliveryAddressPreferences: [],
        };
      }

      const updatedCart = await updateBuyerIdentity(cartId, payload);

      if (updatedCart?.checkoutUrl) {
        setSessionValue("updated_checkout_url", updatedCart.checkoutUrl);
      }
    } catch (_error) {
      // Fail silently – payment flow should still work even if this sync fails
    }
  }

  const isPartialPayment = (rule) => {
    if (rule.amount_type === "cod") return false;
    if (rule.amount_type === "percentage" && rule.amount === "100.0")
      return false;
    return true;
  };

  $: partialPaymentEnabledForUi = (() => {
    const s =
      settings || $settingsStore || $appStore.settings;
    return !!(
      s?.partialPaymentEnabled === true ||
      s?.partial_payment_enabled === true ||
      s?.partial_payment_enabled === "true"
    );
  })();
  $: showNoEligiblePartialBlock =
    noEligiblePartialRules && partialPaymentEnabledForUi;
  $: noRuleQualifiedUserMessage = T("no_rule_qualified");

  $: _primaryBtnDeps = [
    selectedRule,
    ruleSets,
    isCreatingOrder,
    isProcessingPayment,
    otpState?.currentCartData?.items?.length,
    $appStore.settings,
    noEligiblePartialRules,
  ];
  $: {
    const s = $settingsStore || $appStore.settings;
    const partialPaymentOn = !!(
      s?.partialPaymentEnabled === true ||
      s?.partial_payment_enabled === true ||
      s?.partial_payment_enabled === "true"
    );
    if (noEligiblePartialRules && partialPaymentOn) {
      actions.setPrimaryButton({
        label: uiText("cta_close", null, s),
        loading: false,
        disabled: false,
        action: "close_modal",
      });
    } else {
    const codFormEnabled = !!(
      s?.cod_form_enabled === true ||
      s?.cod_form_enabled === "true" ||
      s?.codFormEnabled === true ||
      s?.codFormEnabled === "true"
    );
    let pp = s?.private_payment_provider ?? s?.privatePaymentProvider;
    if (typeof pp === "string") {
      try {
        pp = JSON.parse(pp);
      } catch {
        pp = /razorpay|api_key|api_key_id/.test(pp)
          ? { name: "razorpay" }
          : null;
      }
    }
    const hasPaymentProvider = !!(
      pp &&
      typeof pp === "object" &&
      (pp.name || pp.api_key || pp.api_key_id || pp.secret)
    );
    const selectedRuleObj =
      selectedRule && ruleSets?.length
        ? ruleSets.find((r) => String(r.id) === String(selectedRule))
        : null;
    const isCodRule = selectedRuleObj?.amount_type === "cod";

    let label = uiText("cta_proceed", null, s);
    let action = "submit";
    if (isCodRule && codFormEnabled) {
      label = uiText("cta_complete_order", null, s);
      action = "complete_order";
    } else if (!isCodRule && selectedRuleObj && hasPaymentProvider) {
      label = uiText("cta_pay_now", null, s);
      action = "pay_now";
    }

    const loading = isCreatingOrder || isProcessingPayment;
    const disabled = loading || !otpState?.currentCartData?.items?.length;
    actions.setPrimaryButton({ label, loading, disabled, action });
    }
  }
  const getExistingOrderLevelDiscountDecimal = (cartData) => {
    const apps = cartData?.cart_level_discount_applications || [];
    return (
      apps.reduce((sum, d) => sum + (d?.total_allocated_amount || 0), 0) / 100
    );
  };

  const getRuleOrderLevelDiscountDecimal = (rule, originalCartTotalDecimal) => {
    const ruleDiscountValueNum = parseFloat(
      String(rule?.discount_value ?? "0"),
    );
    const ruleDiscountType = rule?.discount_type || "";
    if (!(rule?.discount_code || "").trim() || !(ruleDiscountValueNum > 0))
      return 0;
    const cartData = otpState?.currentCartData || {};
    const lineLevelDiscountDecimal = (cartData?.items || []).reduce(
      (sum, item) => {
        if (!item?.line_level_discount_allocations?.length) return sum;
        const cents =
          item?.line_level_total_discount ||
          (item.line_level_discount_allocations || []).reduce(
            (s, a) => s + (a?.amount || 0),
            0,
          );
        return sum + cents / 100;
      },
      0,
    );
    const base = Math.max(
      0,
      originalCartTotalDecimal - lineLevelDiscountDecimal,
    );
    return ruleDiscountType === "percentage"
      ? (base * ruleDiscountValueNum) / 100
      : ruleDiscountValueNum;
  };

  const getDiscountBadgeText = (rule) => {
    const cartData = otpState?.currentCartData || {};
    const originalCartTotalDecimal =
      typeof cartData?.original_total_price === "number"
        ? cartData.original_total_price / 100
        : ((cartData?.total_price || 0) + (cartData?.total_discount || 0)) /
          100;
    const existingDiscount = getExistingOrderLevelDiscountDecimal(cartData);
    const ruleDiscount = getRuleOrderLevelDiscountDecimal(
      rule,
      originalCartTotalDecimal,
    );
    const finalDiscount = Math.max(existingDiscount, ruleDiscount);
    if (!(finalDiscount > 0)) return "";
    if (
      rule?.discount_type === "percentage" &&
      ruleDiscount >= existingDiscount
    ) {
      return T("discount_badge_percent", {
        percent: convertFloatToInt(rule.discount_value),
      });
    }
    return T("discount_badge_amount", {
      amount: formatCurrencyHelper(finalDiscount, currencyCode),
    });
  };

  const getRuleSavedAmount = (rule) => {
    const cartData = otpState?.currentCartData || {};
    const originalCartTotalDecimal =
      typeof cartData?.original_total_price === "number"
        ? cartData.original_total_price / 100
        : ((cartData?.total_price || 0) + (cartData?.total_discount || 0)) / 100;
    const existingDiscount = getExistingOrderLevelDiscountDecimal(cartData);
    const ruleDiscount = getRuleOrderLevelDiscountDecimal(
      rule,
      originalCartTotalDecimal,
    );
    return existingDiscount + ruleDiscount;
  };

  // A percentage rule reports the percentage the merchant configured; anything
  // else derives it from the saving as a share of the pre-discount cart.
  const getRuleSavedPercent = (rule) => {
    if (rule?.discount_type === "percentage") {
      const configured = parseFloat(rule.discount_value);
      if (Number.isFinite(configured) && configured > 0) {
        return convertFloatToInt(configured);
      }
    }
    const cartData = otpState?.currentCartData || {};
    const originalCartTotalDecimal =
      typeof cartData?.original_total_price === "number"
        ? cartData.original_total_price / 100
        : ((cartData?.total_price || 0) + (cartData?.total_discount || 0)) / 100;
    if (!(originalCartTotalDecimal > 0)) return 0;
    const saved = getRuleSavedAmount(rule);
    if (!(saved > 0)) return 0;
    return Math.round((saved / originalCartTotalDecimal) * 100);
  };

  // Percentage rules show the percentage, everything else shows the money —
  // same split as the discount badge above.
  const getSaveLineKey = (rule) =>
    rule?.discount_type === "percentage" && getRuleSavedPercent(rule) > 0
      ? "option_save_percent"
      : "option_save";

  const getCustomSaveText = (rule) => String(rule?.custom_save_text ?? "").trim();

  const hasSaveLine = (rule) =>
    !!getCustomSaveText(rule) ||
    (hasRuleDiscount(rule) && getRuleSavedAmount(rule) > 0);

  const escapeHtml = (s) =>
    String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");

  const boldifyAmounts = (text) => {
    let done = false;
    return escapeHtml(text).replace(
      /((?:₹|Rs\.?|C\$|A\$|\$|€|£|¥)\s?\d[\d,]*(?:\.\d+)?)/g,
      (match) => {
        if (done) return match;
        done = true;
        return `<strong class="option-amount">${match}</strong>`;
      },
    );
  };

  $: hasPaymentProvider = (() => {
    const s = $settingsStore || settings || $appStore?.settings;
    let pp = s?.private_payment_provider ?? s?.privatePaymentProvider;
    if (typeof pp === "string") {
      try {
        pp = JSON.parse(pp);
      } catch {
        pp = /razorpay|api_key|api_key_id/.test(pp) ? { name: "razorpay" } : null;
      }
    }
    return !!(
      pp &&
      typeof pp === "object" &&
      (pp.name || pp.api_key || pp.api_key_id || pp.secret)
    );
  })();

  function isDirectCodRule(rule) {
    if (!rule || rule.amount_type !== "cod") return false;
    const s = $settingsStore || settings || $appStore?.settings;
    return !!(
      s?.cod_form_enabled === true ||
      s?.cod_form_enabled === "true" ||
      s?.codFormEnabled === true ||
      s?.codFormEnabled === "true"
    );
  }

  $: codConfirmFee =
    codConfirmRule?.amount_type === "cod" && parseFloat(codConfirmRule?.amount) > 0
      ? parseFloat(codConfirmRule.amount)
      : 0;

  $: onlineUpsellRule = (() => {
    if (!hasPaymentProvider || !ruleSets?.length) return null;
    const full = ruleSets.find(
      (r) => r.amount_type === "percentage" && parseFloat(r.amount) === 100,
    );
    return full || ruleSets.find((r) => r.amount_type !== "cod") || null;
  })();

  $: onlineUpsellSavings = (() => {
    if (!onlineUpsellRule) return 0;
    const codDiscount = codConfirmRule ? getRuleSavedAmount(codConfirmRule) : 0;
    const onlineDiscount = getRuleSavedAmount(onlineUpsellRule);
    return codConfirmFee + Math.max(0, onlineDiscount - codDiscount);
  })();

  function dismissCodConfirm() {
    showCodConfirm = false;
  }

  async function confirmCodOrder() {
    showCodConfirm = false;
    await handleCompleteOrder();
  }

  async function payOnlineInstead() {
    showCodConfirm = false;
    if (!onlineUpsellRule) return;
    handleSelect(onlineUpsellRule.id);
    await tick();
    dispatch("proceed");
  }
  // Optimized: allow rule init before the cart is ready (parallel fetch).
  // Off: original behavior — only init once the cart is ready.
  $: if (
    hasInitialized &&
    (optimizedBuyNow || otpState.isCartReady) &&
    !isInitializing &&
    ruleSets.length === 0 &&
    !noEligiblePartialRules
  ) {
    initialize();
  }
  // Reconcile (optimized only): once the authoritative cart lands
  // (isSummaryOptimistic cleared), re-filter so total/product/collection rules
  // reflect the real cart, not the scraped preview. Runs exactly once.
  $: if (
    optimizedBuyNow &&
    hasInitialized &&
    $otpStore.isCartReady &&
    !$otpStore.isSummaryOptimistic &&
    !isInitializing &&
    !didReconcileRealCart
  ) {
    didReconcileRealCart = true;
    initialize();
  }
  $: if (
    !isLoaderLoading &&
    ruleSets.length > 0 &&
    !didAutoSelectFirstRule &&
    !selectedRule
  ) {
    handleSelect(ruleSets[0].id);
    didAutoSelectFirstRule = true;
  }
  $: if (
    !isLoaderLoading &&
    ruleSets.length === 0 &&
    hasInitialized &&
    !(noEligiblePartialRules && partialPaymentEnabledForUi)
  ) {
    goToNextStep();
  }

  const isFreeDeliveryRule = (rule) =>
    rule?.free_delivery === true || rule?.free_delivery === "true";

  async function initialize() {
    // Optimized: no isCartReady gate — start fetching payment rules in parallel
    // with the cart clear/add/fetch chain (initializeCartAndRules waits for the
    // cart internally). Off: original gate — require the cart to be ready first.
    if (!optimizedBuyNow && !$otpStore.isCartReady) return;
    if (isInitializing) {
      reinitPending = true;
      return;
    }
    // Runaway guard: if a reactive keeps re-triggering initialize() (e.g. rule
    // filtering repeatedly yields an empty set), cap it so the tab can't freeze.
    const now = Date.now();
    initCallTimestamps = initCallTimestamps.filter((t) => now - t < 3000);
    initCallTimestamps.push(now);
    if (initCallTimestamps.length > 12) {
      console.warn(
        "[codk] initialize() runaway suppressed — re-init loop detected",
        { calls: initCallTimestamps.length, ruleSets: ruleSets.length, noEligiblePartialRules },
      );
      return;
    }
    isInitializing = true;
    otpStoreActions.setIsLoaderLoading(true);
    if (!selectedRule) didAutoSelectFirstRule = false;
    await initializeCartAndRules(
      (val) => (cartTotal = val),
      (val) => (ruleSets = val),
      (val) => {
        // Drop a selection the refilter just removed (e.g. newly blocked email).
        const stillAvailable =
          selectedRule &&
          ruleSets.some((r) => String(r.id) === String(selectedRule));
        if (!stillAvailable) selectedRule = val;
      },
      (val) => {
        isFullPercentage = val;
        otpStoreActions.setIsFullPercentage(val);
      },
      (val) => {
        isCOD = val;
        otpStoreActions.setIsCOD(val);
      },
      (val) => otpStoreActions.setIsLoaderLoading(val),
    );
    // initializeCartAndRules may have just fetched the rules into the session.
    needsCartItemCount = rulesNeedCartItemCount(getSessionValue("ruleSets"));
    const rawNoEligible = getSessionValue("partial_payment_no_eligible_rules");
    noEligiblePartialRules =
      rawNoEligible === true || rawNoEligible === "true";
    isInitializing = false;
    if (reinitPending) {
      reinitPending = false;
      initialize();
    }
  }

  async function goToNextStep() {
    try {
      otpStoreActions.setIsPartialPaymentCartReadyAndUpdated(true);
      otpStoreActions.setStep(await getCurrentStep());
    } catch (_err) {}
  }

  function handleSelect(id) {
    handleRuleSelection(
      id,
      ruleSets,
      (val) => (selectedRule = val),
      (msg) => flashMessage((v) => (error = v), msg),
      (val) => {
        isCOD = val;
        otpStoreActions.setIsCOD(val);
      },
      (val) => {
        isFullPercentage = val;
        otpStoreActions.setIsFullPercentage(val);
      },
    );
  }

  async function selectAndProceed(id) {
    const rule = ruleSets.find((r) => String(r.id) === String(id));
    const needsConfirm = isDirectCodRule(rule);
    if (!needsConfirm) otpStoreActions.setIsProceedingPayment(true);
    handleSelect(id);
    await tick();
    if (needsConfirm) {
      codConfirmRule = rule;
      showCodConfirm = true;
      return;
    }
    dispatch("proceed");
  }

  const getPrice = (rule) =>
    calculateRulePrice(
      rule,
      cartTotal,
      orderSummary,
      currencyCode,
      ruleShipping(rule),
    );
  const formatMoneyCompact = (amount) => {
    try {
      return formatCurrencyHelper(parseFloat(amount), currencyCode);
    } catch {
      return String(amount);
    }
  };
  const getDescText = (rule) =>
    settings?.partialPaymentFlowVersion === 2
      ? getDescBundle(rule, otpState.currentCartData, null, ruleShipping(rule))
      : generateRuleDescription(
          rule,
          cartTotal,
          orderSummary,
          currencyCode,
          getPrice,
          ruleShipping(rule),
        );

  const getDescTextWithTax = (rule, ruleTax, remainingTax) => {
    const { payNow, totalAfterDiscount } = getPayNowAmount(rule);
    const totalTax = ruleTax + remainingTax;
    const ship = ruleShipping(rule);

    // For COD - show total amount with tax on delivery
    if (rule?.amount_type === "cod") {
      const codFee = parseFloat(rule?.amount) || 0;
      const totalOnDelivery = totalAfterDiscount + codFee + totalTax + ship;
      const totalFormatted = formatCurrencyHelper(
        totalOnDelivery,
        currencyCode,
      );
      const codFeeFormatted = formatCurrencyHelper(codFee, currencyCode);
      if (codFee > 0) {
        return T("desc_cod_with_fee", {
          total: totalFormatted,
          cod_fee: codFeeFormatted,
        });
      }
      return T("desc_cod", { total: totalFormatted });
    }

    // For 100% payment (Full Payment) - show total with tax
    if (
      rule?.amount_type === "percentage" &&
      parseFloat(rule?.amount) === 100
    ) {
      const totalWithTax = totalAfterDiscount + totalTax + ship;
      const totalFormatted = formatCurrencyHelper(totalWithTax, currencyCode);
      const discount = orderSummary?.discount || 0;
      if (discount > 0) {
        const discountFormatted = formatCurrencyHelper(discount, currencyCode);
        return T("desc_prepaid_with_discount", {
          pay_now: totalFormatted,
          discount: discountFormatted,
        });
      }
      return T("desc_prepaid", { pay_now: totalFormatted });
    }

    // For partial payments
    const remaining = Math.max(0, totalAfterDiscount - payNow);

    // Include tax in amounts; shipping is collected with the delivery leg
    const payNowWithTax = payNow + ruleTax;
    const remainingWithTax = remaining + remainingTax + ship;

    const payNowFormatted = formatCurrencyHelper(payNowWithTax, currencyCode);
    const remainingFormatted = formatCurrencyHelper(
      remainingWithTax,
      currencyCode,
    );

    if (remaining <= 0 || remainingWithTax <= 0) {
      return T("desc_pay_now_only", { pay_now: payNowFormatted });
    }

    return T("desc_partial", {
      pay_now: payNowFormatted,
      pay_later: remainingFormatted,
    });
  };

  // Tax-aware description that works with both flow versions
  const getDescTextWithTaxAware = (rule, ruleTax, remainingTax) => {
    // For partialPaymentFlowVersion === 2, use getDescBundle with tax info
    if (settings?.partialPaymentFlowVersion === 2) {
      const cart = otpState.currentCartData;
      if (!cart) return getDescTextWithTax(rule, ruleTax, remainingTax);

      // Pass tax info to getDescBundle which now supports it
      const taxInfo = { ruleTax, remainingTax };
      const desc = getDescBundle(rule, cart, taxInfo, ruleShipping(rule));
      return desc || getDescTextWithTax(rule, ruleTax, remainingTax);
    }

    // Fallback to original function for non-v2 flows
    return getDescTextWithTax(rule, ruleTax, remainingTax);
  };

  function flashMessage(setter, msg, type = "error") {
    const text = String(msg || "").trim();
    if (!text) {
      setter("");
      return;
    }
    toast[type](text).then((shown) => {
      if (shown) return;
      setter(text);
      setTimeout(() => setter(""), 5000);
    });
  }

  function redirectToOrderStatus(url) {
    const target =
      typeof window !== "undefined" && window.top ? window.top : window;
    target.location.href = url;
  }

  export async function handleCompleteOrder() {
    if (isCreatingOrder) return;
    isCreatingOrder = true;
    orderError = "";
    orderSuccessMessage = "";
    codOrderFlowStore.start();
    actions.setShowCodOrderFlow(true);
    try {
      const result = await completeCodOrder({
        otpState,
        selectedRule,
        ruleSets,
        currencyCode,
        selectedShippingRate: effectiveSelectedShippingRate,
        manualShippingCharge: shippingAmount,
        otpStoreActions,
      });
      flashMessage((v) => (orderSuccessMessage = v), result.message, "success");
      // Always show Thank You page (never redirect before user sees it)
      const shippingAddress = resolveShippingAddress(
        otpState,
        otpState?.currentCartData,
      );
      const buyerIdentity = getBuyerIdentity(otpState);
      codOrderFlowStore.success({
        orderNumber: result.orderNumber || null,
        orderStatusUrl: result.orderStatusUrl || null,
        total: computedTotal,
        currencyCode,
        deliveryEstimate: result?.deliveryEstimate ?? null,
        paymentMethod: "Cash on Delivery",
        deliveryAddress: shippingAddress
          ? {
              name:
                [shippingAddress.first_name, shippingAddress.last_name]
                  .filter(Boolean)
                  .join(" ")
                  .trim() || "—",
              address1: shippingAddress.address1 || "",
              address2: shippingAddress.address2 || "",
              city: shippingAddress.city || "",
              province: shippingAddress.province || "",
              zip: shippingAddress.zip || "",
              country: shippingAddress.country || "",
              phone: buyerIdentity?.phone || "",
              email: buyerIdentity?.email || "",
            }
          : null,
      });
    } catch (err) {
      codOrderFlowStore.clear();
      actions.setShowCodOrderFlow(false);
      flashMessage(
        (v) => (orderError = v),
        err.message || "Failed to create order. Please try again.",
      );
    } finally {
      isCreatingOrder = false;
    }
  }

  export async function handleRazorpayPayment() {
    if (isProcessingPayment || !selectedRule) return;
    const buyerIdentity = getBuyerIdentity(otpState);
    if (
      !buyerIdentity?.phone &&
      (!buyerIdentity?.email || !String(buyerIdentity.email).trim())
    ) {
      flashMessage(
        (v) => (orderError = v),
        "Phone number or email is required to place the order.",
      );
      return;
    }
    isProcessingPayment = true;
    orderError = "";
    orderSuccessMessage = "";
    try {
      razorpayEmbedOptions = await initiateRazorpayPayment({
        otpState,
        selectedRule,
        ruleSets,
        currencyCode,
        orderSummary,
        selectedShippingRate: effectiveSelectedShippingRate,
        manualShippingCharge: shippingAmount,
      });
      showRazorpayEmbed = true;
    } catch (err) {
      flashMessage(
        (v) => (orderError = v),
        err.message || "Payment failed. Please try again.",
      );
      showRazorpayEmbed = false;
      isProcessingPayment = false;
    }
  }

  async function handleRazorpayPaymentSuccess(response) {
    orderError = "";
    isProcessingPayment = false;
    showRazorpayEmbed = false;
    // Show order processing screen immediately (like COD) — no orderSuccessMessage
    codOrderFlowStore.start();
    actions.setShowCodOrderFlow(true);
    try {
      const result = await verifyRazorpayAndCreateOrder(
        response,
        otpStoreActions,
      );
      if (!result.success) return; // native event filtered
      const shippingAddress = resolveShippingAddress(
        otpState,
        otpState?.currentCartData,
      );
      const buyerIdentity = getBuyerIdentity(otpState);
      codOrderFlowStore.success({
        orderNumber: result.orderNumber || null,
        orderStatusUrl: result.orderStatusUrl || null,
        total: computedTotal,
        currencyCode,
        deliveryEstimate: result?.deliveryEstimate ?? null,
        paymentMethod: "Online Payment",
        deliveryAddress: shippingAddress
          ? {
              name:
                [shippingAddress.first_name, shippingAddress.last_name]
                  .filter(Boolean)
                  .join(" ")
                  .trim() || "—",
              address1: shippingAddress.address1 || "",
              address2: shippingAddress.address2 || "",
              city: shippingAddress.city || "",
              province: shippingAddress.province || "",
              zip: shippingAddress.zip || "",
              country: shippingAddress.country || "",
              phone: buyerIdentity?.phone || "",
              email: buyerIdentity?.email || "",
            }
          : null,
      });
    } catch (err) {
      codOrderFlowStore.clear();
      actions.setShowCodOrderFlow(false);
      flashMessage(
        (v) => (orderError = v),
        err.message || "Payment verification failed. Please try again.",
      );
    } finally {
      isProcessingPayment = false;
      showRazorpayEmbed = false;
    }
  }

  function handleRazorpayPaymentFailure(err) {
    if (err.message && !err.message.includes("cancelled")) {
      flashMessage(
        (v) => (orderError = v),
        err.message || "Payment failed. Please try again.",
      );
    }
    isProcessingPayment = false;
    showRazorpayEmbed = false;
  }
  export async function handleSubmit() {
    const flowVersion = settings?.partialPaymentFlowVersion;
    if (flowVersion === 2) {
      await handlePartialPaymentSubmitBundle(
        selectedRule,
        ruleSets,
        (v) => (isPartialLoading = v),
        (m) => flashMessage((v) => (error = v), m),
        (v) => otpStoreActions.setIsPartialPaymentCartReadyAndUpdated(v),
        (s) => otpStoreActions.setStep(s),
        cartTotal,
        orderSummary,
      );
    } else {
      await handlePaymentSubmit(
        isFullPercentage,
        isCOD,
        selectedRule,
        ruleSets,
        (v) => (isPartialLoading = v),
        (m) => flashMessage((v) => (error = v), m),
        (v) => otpStoreActions.setIsPartialPaymentCartReadyAndUpdated(v),
        actions.handleSkip,
        (s) => otpStoreActions.setStep(s),
        cartTotal,
        orderSummary,
      );
    }
  }

  async function fetchTaxForSelectedAddress() {
    const s = settings || $settingsStore;
    const prefilledOn = !!(
      s?.isPrefilledAddressEnabled === true ||
      s?.isPrefilledAddressEnabled === "true" ||
      s?.is_prefilled_address_enabled === true ||
      s?.is_prefilled_address_enabled === "true" ||
      s?.cod_form_enabled === true ||
      s?.cod_form_enabled === "true"
    );
    if (!prefilledOn) return;
    const codFormEnabled =
      s?.cod_form_enabled === true ||
      s?.cod_form_enabled === "true" ||
      s?.codFormEnabled === true ||
      s?.codFormEnabled === "true";
    if (
      !codFormEnabled &&
      !(s?.pre_v2_show_tax_info === true || s?.preV2ShowTaxInfo === true) &&
      !showShippingInfo
    ) {
      return;
    }

    if (taxInclusiveMerchant && !showShippingInfo) {
      otpStore.setCalculatedTaxData(null);
      return;
    }

    const address = getSessionValue("cod_king_selected_address");
    if (!address) return;

    const cartData = otpState?.currentCartData;
    if (!cartData?.items?.length) return;

    const shopDomain = getShopDomain();
    if (!shopDomain) return;

    try {
      const result = await calculateTax({
        cart_data: cartData,
        shipping_address: address,
        shop_domain: shopDomain,
      });
      if (result.success && result.tax_calculation) {
        const data = {
          total_tax: result.tax_calculation.total_tax,
          subtotal_price: result.tax_calculation.subtotal_price,
          total_price: result.tax_calculation.total_price,
          tax_lines: result.tax_calculation.tax_lines || [],
          available_shipping_rates:
            result.tax_calculation.available_shipping_rates || [],
          calculated_at: Date.now(),
        };
        otpStore.setCalculatedTaxData(data);
      }
    } catch (_) {}
  }

  onMount(async () => {
    settings = $settingsStore;
    const shopifyCurrency =
      /** @type {any} */ (window?.parent?.Shopify?.currency) ||
      /** @type {any} */ (window?.Shopify?.currency);
    if (shopifyCurrency?.active) currencyCode = shopifyCurrency.active;

    const redirectOrderNumber = getSessionValue(
      "razorpay_redirect_order_number",
    );
    if (
      redirectOrderNumber &&
      getSessionValue("razorpay_redirect_success") === "1"
    ) {
      flashMessage(
        (v) => (orderSuccessMessage = v),
        `Order #${redirectOrderNumber} created successfully!`,
        "success",
      );
      removeSessionValue("razorpay_redirect_order_number");
      removeSessionValue("razorpay_redirect_success");
    }

    unsubscribeAppStore = appStore.subscribe(() => {});
    if (optimizedBuyNow) {
      // Optimized: show the payment skeleton right away and kick off the rule
      // fetch in parallel with the cart chain — don't block hasInitialized on
      // the (cart-dependent) wait.
      otpStoreActions.setIsLoaderLoading(true);
      lastFilteredAddressId = $otpStore?.selectedAddress;
      hasInitialized = true;
      initialize();
      ensureBuyerIdentitySyncedWithCart();
    } else {
      // Original: await init + buyer identity before marking initialized.
      await initialize();
      await ensureBuyerIdentitySyncedWithCart();
      lastFilteredAddressId = $otpStore?.selectedAddress;
      hasInitialized = true;
    }
    window.addEventListener(
      "codk-cart-discount-updated",
      onCartDiscountUpdated,
    );
    window.addEventListener("codk-address-updated", onAddressUpdated);

    fetchTaxForSelectedAddress();
  });

  function onCartDiscountUpdated() {
    if (!hasInitialized) return;
    // Re-run rule filtering for current post-discount total (all flow versions).
    initialize();
  }

  function onAddressUpdated() {
    if (!hasInitialized) return;
    initialize();
    fetchTaxForSelectedAddress();
  }

  onDestroy(() => {
    if (unsubscribeAppStore) unsubscribeAppStore();
    window.removeEventListener(
      "codk-cart-discount-updated",
      onCartDiscountUpdated,
    );
    window.removeEventListener("codk-address-updated", onAddressUpdated);
  });
</script>

<div class="payment-options-section animate-slide-in-up animate-delay-1">
  {#if orderSuccessMessage}
    <div class="order-success-banner" role="alert">{orderSuccessMessage}</div>
  {/if}
  <div class="payment-options-header">
    <h2 class="payment-options-title">{T("payment_options_title")}</h2>
    <span class="payment-options-perk">
      <img
        class="payment-options-bolt"
        src="https://cdn.shopify.com/s/files/1/0776/0058/7973/files/Bolt_2.svg?v=1785233574"
        alt=""
      />
      {T("payment_options_perk")}
    </span>
  </div>

  <div class="payment-options-content">
    <!-- Skeleton for quick view / checkout until the cart is ready; PDP buy now
         has optimistic data so it shows the real cards. Off: isLoaderLoading only. -->
    {#if showPaymentSkeleton}
      <PaymentOptionSkeleton count={3} />
    {:else}
      <div class="options-container" class:disabled={isPartialLoading}>
        {#if showNoEligiblePartialBlock}
          <div class="error-message" role="alert">
            {noRuleQualifiedUserMessage}
          </div>
        {:else if ruleSets.length === 0}
          <div class="error-message">
            {T("no_payment_options")}
          </div>
        {:else}
          <div class="payment-options-list">
            {#each ruleSets as rule, index (rule.id + "-" + (showTaxInfo ? taxRate : 0) + "-" + ruleShippingSignature)}
              {@const _ruleShipping = ruleShipping(rule)}
              {@const _ruleTax = getRuleTax(rule)}
              {@const _remainingTax = getRemainingTax(rule)}
              {@const _totalTax = _ruleTax + _remainingTax}
              {@const _descText =
                showTaxInfo && (_ruleTax > 0 || _remainingTax > 0)
                  ? getDescTextWithTaxAware(rule, _ruleTax, _remainingTax)
                  : getDescText(rule)}
              <div
                class="payment-option-card"
                class:selected={selectedRule === rule.id}
                on:click={() => selectAndProceed(rule.id)}
                on:keydown={(e) =>
                  (e.key === "Enter" || e.key === " ") && selectAndProceed(rule.id)}
                role="button"
                tabindex="0"
              >
                <div class="radio-icon" aria-hidden="true">
                  {#if rule.amount_type === "cod"}
                    <svg
                      width="16"
                      height="16"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="#404040"
                      stroke-width="1.5"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <path d="M3 7h11v10H3z" /><path
                        d="M14 10h4l3 3v4h-7"
                      /><circle cx="7" cy="19" r="1.5" /><circle
                        cx="17"
                        cy="19"
                        r="1.5"
                      />
                    </svg>
                  {:else}
                    <svg
                      width="16"
                      height="16"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="#404040"
                      stroke-width="1.5"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <rect x="3" y="6" width="18" height="12" rx="2" /><path
                        d="M3 10h18"
                      /><path d="M7 15h4" />
                    </svg>
                  {/if}
                  {#if rule.amount_type === "percentage" && parseFloat(rule.amount) === 100}
                    <img
                      class="radio-icon-bolt"
                      src="https://cdn.shopify.com/s/files/1/0776/0058/7973/files/Bolt_2.svg?v=1785233574"
                      alt=""
                    />
                  {/if}
                </div>

                <div class="payment-option-content">
                  <span class="option-name">{rule.rule_name}</span>
                  <div class="option-description">
                    <div class="option-description-text" data-rule-id={rule.id}>
                      {@html boldifyAmounts(_descText)}
                    </div>
                  </div>
                  {#if hasSaveLine(rule) || (rule.amount_type === "cod" && rule.amount > 0) || _ruleShipping > 0 || isFreeDeliveryRule(rule) || rule.repeat_customer_applied}
                    <div class="option-meta">
                      {#if hasSaveLine(rule)}
                        <span class="option-save-line">
                          <img
                            class="option-save-icon"
                            src="https://cdn.shopify.com/s/files/1/0776/0058/7973/files/discount_icon-ezgif.com-resize_1.gif?v=1784542496"
                            alt=""
                          />
                          {getCustomSaveText(rule) ||
                            T(getSaveLineKey(rule), {
                              amount: formatCurrencyHelper(
                                getRuleSavedAmount(rule),
                                currencyCode,
                              ),
                              percent: getRuleSavedPercent(rule),
                            })}
                        </span>
                      {/if}
                      {#if rule.amount_type === "cod" && rule.amount > 0}
                        <span class="cod-badge"
                          >{T("cod_fee_badge", {
                            amount: formatMoneyCompact(rule.amount),
                          })}</span
                        >
                      {/if}
                      {#if isFreeDeliveryRule(rule)}
                        <span class="free-delivery-badge">
                          {T("free_delivery_badge")}
                          <img
                            class="free-delivery-emoji"
                            src="https://cdn.shopify.com/s/files/1/0776/0058/7973/files/CelebrationEmoji.png?v=1784797043"
                            alt=""
                          />
                        </span>
                      {/if}
                      {#if _ruleShipping > 0}
                        <span class="shipping-badge"
                          >{String(rule?.shipping_charge_text ?? "").trim()
                            ? interpolate(String(rule.shipping_charge_text).trim(), {
                                amount: formatMoneyCompact(_ruleShipping),
                              })
                            : T("shipping_fee_badge", {
                                amount: formatMoneyCompact(_ruleShipping),
                              })}</span
                        >
                      {/if}
                    </div>
                  {/if}
                </div>

                <div class="price-section">
                  <div class="price-row">
                    {#if (orderSummary?.hasDiscount || getRuleSavedAmount(rule) > 0) && (rule.amount_type === "cod" || (rule.amount_type === "percentage" && parseFloat(rule.amount) === 100))}
                      {#if rule.amount_type !== "cod" || orderSummary.originalTotal > orderSummary.total}
                        <span class="original-price"
                          >{formatCurrencyHelper(
                            orderSummary.originalTotal,
                            currencyCode,
                          )}</span
                        >
                      {/if}
                    {/if}
                    <span class="final-price">
                      {settings?.partialPaymentFlowVersion === 2
                        ? getPriceBundle(
                            rule,
                            otpState.currentCartData,
                            _ruleShipping,
                          )
                        : getPrice(rule)}
                    </span>
                  </div>
                  {#if showTaxInfo && taxRate > 0 && _ruleTax > 0}
                    <div class="rule-tax-hint">
                      {T("tax_hint", {
                        amount: formatCurrencyHelper(_ruleTax, currencyCode),
                      })}
                    </div>
                  {/if}
                </div>
                <img
                  class="payment-option-arrow"
                  src="https://cdn.shopify.com/s/files/1/0776/0058/7973/files/arrowIconCard.svg?v=1785234513"
                  alt=""
                  aria-hidden="true"
                />
              </div>
            {/each}
          </div>
          {#if taxNote}
            <div class="option-note">* {taxNote}</div>
          {/if}
        {/if}
      </div>
    {/if}

    {#if error}
      <div class="error-display">{error}</div>
    {/if}

    {#if orderSuccessMessage || orderError}
      <div class="complete-order-section">
        {#if orderSuccessMessage}
          <div class="order-success-message">{orderSuccessMessage}</div>
        {/if}
        {#if orderError}
          <div class="order-error-message">{orderError}</div>
        {/if}
      </div>
    {/if}
  </div>
</div>

{#if showRazorpayEmbed && razorpayEmbedOptions}
  <RazorpayEmbed
    open={showRazorpayEmbed}
    razorpayOptions={razorpayEmbedOptions}
    onSuccess={(response) => handleRazorpayPaymentSuccess(response)}
    on:success={(e) => handleRazorpayPaymentSuccess(e.detail)}
    onFailure={(error) => handleRazorpayPaymentFailure(error)}
    on:close={() => {
      showRazorpayEmbed = false;
      isProcessingPayment = false;
    }}
  />
{/if}

<Sheet
  open={showCodConfirm}
  title={T("confirm_sheet_title")}
  headerBorder={false}
  headerBanner={true}
  closeLabel="Close"
  dismiss={dismissCodConfirm}
>
  <Card variant="soft" padding="snug" attach="bottom">
    <div class="cod-confirm">
    <div class="cod-confirm-total-row">
      <span class="cod-confirm-total-label">
        {T("total_amount_inline")}
        <span class="cod-confirm-total-value"
          >{formatCurrencyHelper(computedTotal, currencyCode)}</span
        >
      </span>
      {#if codConfirmFee > 0}
        <span class="cod-confirm-fee-pill">
          Incl. {formatCurrencyHelper(codConfirmFee, currencyCode)} COD charges
        </span>
      {/if}
    </div>

    <div class="cod-confirm-actions">
      <button
        type="button"
        class="cod-confirm-btn cod-confirm-btn--primary"
        on:click={confirmCodOrder}
        disabled={isCreatingOrder}
      >
        {T("cta_confirm_order")}
      </button>
      {#if onlineUpsellRule}
        <button
          type="button"
          class="cod-confirm-btn cod-confirm-btn--secondary"
          on:click={payOnlineInstead}
        >
          <span
            >Pay online{#if onlineUpsellSavings > 0} (save upto <span
                class="cod-confirm-save"
                >{formatCurrencyHelper(onlineUpsellSavings, currencyCode)}</span
              >){/if}</span
          >
        </button>
      {/if}
    </div>
    </div>
  </Card>
</Sheet>
