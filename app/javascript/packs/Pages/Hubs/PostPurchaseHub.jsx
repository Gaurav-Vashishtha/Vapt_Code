import React, { useContext, useCallback } from "react";
import { StoreContext } from "../../Context/Store";
import I18n from "../../i18n-lang";
import Api from "../../Services/Api";
import SectionHub from "../../Components/SectionHub";

const PostPurchaseHub = () => {
  const {
    setting: [setting, setSetting],
  } = useContext(StoreContext);

  const saveSetting = useCallback(
    async (patch) => {
      const response = await Api.post("/settings", { ...setting, ...patch });
      if (response?.data) setSetting(response.data);
    },
    [setting, setSetting],
  );

  const items = [
    {
      title: I18n.t("admin.thankyou_page_otp", { defaultValue: "Thank-you Page OTP" }),
      description:
        I18n.t("admin.thankyou_page_otp_description", { defaultValue: "Verify orders after checkout on the Thank-you and Order-status pages." }),
      enabled: !!(setting?.postOrderOtp?.thankYouPage || setting?.enablePreOrderOtp),
      noStatus: !setting,
      href: "/features/post-order-otp",
    },
    {
      title: I18n.t("onboarding.convert_heading", { defaultValue: "COD to Prepaid" }),
      description:
        I18n.t("admin.cod_to_prepaid_description", { defaultValue: "Nudge COD customers to pay online after purchase." }),
      enabled: !!setting?.prepaidEnabled,
      href: "/features/cod-to-prepaid",
      onToggle: (next) => saveSetting({ prepaidEnabled: next }),
    },
  ];

  return (
    <SectionHub
      title={I18n.t("nav.post_purchase", { defaultValue: "Post Purchase" })}
      subtitle={
        I18n.t("admin.post_purchase_hub_subtitle", { defaultValue: "Recover and convert orders after checkout." })
      }
      items={items}
    />
  );
};

export default PostPurchaseHub;
