import React, { useContext, useEffect, useState, useCallback } from "react";
import { StoreContext } from "../../Context/Store";
import I18n from "../../i18n-lang";
import Api from "../../Services/Api";
import SectionHub from "../../Components/SectionHub";
import CheckoutFormPreview from "../../Components/CheckoutPreview/CheckoutFormPreview";
import { shopHasFullPaymentPrepaidDiscount } from "../../utils/paidPlanDowngradeBlockers";

const CheckoutHub = () => {
  const {
    shop: [shop],
    setting: [setting, setSetting],
  } = useContext(StoreContext);

  const [prepaidDiscountEnabled, setPrepaidDiscountEnabled] = useState(false);

  useEffect(() => {
    if (!shop?.id) return;
    Api.get("/partial_rule_sets")
      .then((response) => {
        const rules = Array.isArray(response?.data) ? response.data : [];
        setPrepaidDiscountEnabled(
          shopHasFullPaymentPrepaidDiscount(setting, rules),
        );
      })
      .catch(() => setPrepaidDiscountEnabled(false));
  }, [shop?.id, setting?.partialPaymentEnabled]);

  const saveSetting = useCallback(
    async (patch) => {
      const response = await Api.post("/settings", { ...setting, ...patch });
      if (response?.data) setSetting(response.data);
    },
    [setting, setSetting],
  );

  const items = [
    {
      title: I18n.t("admin.otp_verification", { defaultValue: "OTP Verification" }),
      description:
        I18n.t("admin.otp_description", { defaultValue: "Verify COD orders with a pre-order OTP." }),
      enabled: !!setting?.enablePreOrderOtp,
      href: "/features/otp/pre-order",
      onToggle: (next) => saveSetting({ enablePreOrderOtp: next }),
    },
    {
      title: I18n.t("admin.partial_heading", { defaultValue: "Partial Payment" }),
      description:
        I18n.t("admin.partial_description", { defaultValue: "Collect an advance to reduce fake COD orders." }),
      enabled: !!setting?.partialPaymentEnabled,
      href: "/features/partial-payment",
      onToggle: (next) => saveSetting({ partialPaymentEnabled: next }),
    },
    {
      title: I18n.t("admin.address_prefill", { defaultValue: "Address Prefill" }),
      description:
        I18n.t("admin.address_prefill_description", { defaultValue: "Prefill the customer's address to speed up checkout." }),
      enabled: !!setting?.isPrefilledAddressEnabled,
      href: "/checkout/address-prefill",
      onToggle: (next) => saveSetting({ isPrefilledAddressEnabled: next }),
    },
    {
      title: I18n.t("admin.discounts", { defaultValue: "Discounts" }),
      description:
        I18n.t("admin.discounts_description", { defaultValue: "Offer discounts on the COD King form." }),
      noStatus: true,
      href: "/features/discounts",
    },
    {
      title: I18n.t("admin.prepaid_discount", { defaultValue: "Prepaid Discount" }),
      description:
        I18n.t("admin.prepaid_discount_description", { defaultValue: "Reward customers who pay upfront." }),
      enabled: !!(setting?.partialPaymentEnabled && prepaidDiscountEnabled),
      href: "/features/prepaid-discount",
      isNew: true,
    },
  ];

  return (
    <SectionHub
      title={I18n.t("nav.checkout", { defaultValue: "Form / COD King Checkout" })}
      subtitle={
        I18n.t("admin.checkout_hub_subtitle", { defaultValue: "Configure the COD King checkout form. Changes are reflected in the live preview." })
      }
      items={items}
      preview={<CheckoutFormPreview setting={setting} />}
    />
  );
};

export default CheckoutHub;
