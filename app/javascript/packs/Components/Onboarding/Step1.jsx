import React, { useCallback, useContext } from "react";
import { Card } from "@shopify/polaris";
import I18n from "../../i18n-lang";

const Step1 = () => {
  <Card
    title={I18n.t("step1.connect_with_wish")}
    secondaryFooterActions={[{ content: I18n.t("step1.back") }]}
    primaryFooterAction={{ content: I18n.t("step1.connect_with_wish") }}
  ></Card>;
};

export default Step1;
