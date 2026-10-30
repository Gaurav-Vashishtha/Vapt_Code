import React from "react";
import { Card, EmptyState } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { t } from "./format";

const ConnectEmptyState = () => (
  <Card>
    <EmptyState
      heading={t("connect.title", "Connect your WhatsApp number to start receiving customer messages")}
      image="https://cdn.shopify.com/s/files/1/0262/4071/2726/files/emptystate-files.png"
      action={{
        content: t("connect.cta", "Connect WhatsApp number"),
        onAction: () => navigateTo("/features/whatsapp/account"),
      }}
    >
      <p>
        {t(
          "connect.body",
          "Once your number is connected, every customer message shows up here so your team can reply from COD King.",
        )}
      </p>
    </EmptyState>
  </Card>
);

export default ConnectEmptyState;
