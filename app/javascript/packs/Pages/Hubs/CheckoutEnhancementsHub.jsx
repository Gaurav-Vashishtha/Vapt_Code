import React, { useContext, useEffect, useRef, useState, useCallback } from "react";
import { StoreContext } from "../../Context/Store";
import I18n from "../../i18n-lang";
import Api from "../../Services/Api";
import SectionHub from "../../Components/SectionHub";

const CheckoutEnhancementsHub = () => {
  const {
    shop: [shop],
    setting: [setting, setSetting],
  } = useContext(StoreContext);

  const saveSetting = useCallback(
    async (patch) => {
      const response = await Api.post("/settings", { ...setting, ...patch });
      if (response?.data) setSetting(response.data);
    },
    [setting, setSetting],
  );

  const [codShowHideEnabled, setCodShowHideEnabled] = useState(false);
  const mountedRef = useRef(true);

  useEffect(() => {
    if (!shop?.id) return undefined;
    Api.get("/settings/is_cod_show_hide_enabled")
      .then((response) => {
        const enabled =
          response?.data?.isCodShowHideEnabled ??
          response?.data?.data?.isCodShowHideEnabled ??
          false;
        if (mountedRef.current) setCodShowHideEnabled(!!enabled);
      })
      .catch(() => {
        if (mountedRef.current) setCodShowHideEnabled(false);
      });
    return () => {
      mountedRef.current = false;
    };
  }, [shop?.id]);

  const items = [
    {
      title: I18n.t("admin.cod_fees", { defaultValue: "COD Fees" }),
      description:
        I18n.t("admin.cod_fees_description", { defaultValue: "Add a fee to COD orders to offset RTO costs." }),
      enabled: !!(setting?.codFeeEnabled || setting?.enableShippingCodFees),
      href: "/features/cod-fees",
      onToggle: (next) => saveSetting({ codFeeEnabled: next }),
    },
    {
      title: I18n.t("admin.cod_show_hide", { defaultValue: "COD Show / Hide" }),
      description:
        I18n.t("admin.cod_show_hide_description", { defaultValue: "Control which customers see COD at checkout." }),
      enabled: codShowHideEnabled,
      href: "/features/limit-cod",
    },
  ];

  return (
    <SectionHub
      title={I18n.t("nav.checkout_enhancements", { defaultValue: "Shopify Checkout / COD Enhancements" })}
      subtitle={
        I18n.t("admin.checkout_enhancements_hub_subtitle", { defaultValue: "Fine-tune how COD behaves in the native Shopify checkout." })
      }
      items={items}
    />
  );
};

export default CheckoutEnhancementsHub;
