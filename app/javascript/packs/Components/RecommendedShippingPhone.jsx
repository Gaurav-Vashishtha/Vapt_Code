import React, { useState, useContext, useEffect } from "react";
import {
  Card,
  Button,
  Link,
  Banner,
  List,
  CalloutCard,
  FormLayout,
} from "@shopify/polaris";
import I18n from "../i18n-lang";
import { StoreContext } from "../Context/Store";
// import Mobile from "../Assets/mobile"

const RecommendedShippingPhone = () => {
  const {
    shop: [shop],
  } = useContext(StoreContext);
  return (
    <CalloutCard
      title={I18n.t("recommended_shipping_phone.make_the_phone_number_field_a")}
      illustration={"NA"}
      primaryAction={{
        primary: true,
        content: I18n.t("recommended_shipping_phone.open_checkout_settings_2"),
        url: `https://${shop.shopify_domain}/admin/settings/checkout`,
      }}
      secondaryAction={{
        primary: false,
        content: I18n.t("recommended_shipping_phone.quick_video_10_seconds"),
        external: true,
        url: "https://github.com/amandeep009/resources/blob/6f0c3497e145668bff4641f3802ed93b87762435/phoneNumberMandatory.gif?raw=true",
      }}
    >
      <p>
        <b>
          <u> {I18n.t("recommended_shipping_phone.follow_below_steps")}</u>
        </b>
      </p>
      <p>
        {" "}
        {I18n.t("recommended_shipping_phone.step_click_on", {
          target: I18n.t("recommended_shipping_phone.open_checkout_settings"),
        })}
      </p>
      <p>
        {" "}
        {I18n.t("recommended_shipping_phone.step_scroll_down_on", {
          target: I18n.t("recommended_shipping_phone.customer_information"),
        })}
      </p>
      <p>
        {" "}
        {I18n.t("recommended_shipping_phone.step_ensure_required", {
          target: I18n.t("recommended_shipping_phone.shipping_phone_number"),
        })}
      </p>
    </CalloutCard>
  );
};

export default RecommendedShippingPhone;
