import React, { useContext, useEffect, useState } from "react";
import { Banner } from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import I18n from "../../i18n-lang";
import Api from "../../Services/Api";
import SectionHub from "../../Components/SectionHub";

const MessagingHub = () => {
  const {
    shop: [shop],
    setting: [setting],
  } = useContext(StoreContext);

  const [brandedConnected, setBrandedConnected] = useState(false);
  const [webhooksConnected, setWebhooksConnected] = useState(false);

  useEffect(() => {
    if (!shop?.id) return undefined;
    let cancelled = false;
    Api.get("/api/whatsapp/account")
      .then((response) => {
        const connected =
          response?.data?.connected ?? response?.data?.data?.connected ?? false;
        if (!cancelled) setBrandedConnected(!!connected);
      })
      .catch(() => {
        if (!cancelled) setBrandedConnected(false);
      });
    return () => {
      cancelled = true;
    };
  }, [shop?.id]);

  useEffect(() => {
    if (!shop?.id) return undefined;
    let cancelled = false;
    Api.get("/api/webhooks/endpoints")
      .then((response) => {
        const list = response?.data?.endpoints || [];
        if (!cancelled) {
          setWebhooksConnected(list.some((e) => e.enabled && e.lastReceivedAt));
        }
      })
      .catch(() => {
        if (!cancelled) setWebhooksConnected(false);
      });
    return () => {
      cancelled = true;
    };
  }, [shop?.id]);

  const codKingWhatsappEnabled = !!(
    setting?.confirmationWhatsapp ||
    setting?.fulfilmentWhatsapp ||
    setting?.acWhatsapp ||
    setting?.sendVerificationLinkOnly
  );

  const items = [
    {
      title: I18n.t("admin.cod_king_whatsapp", { defaultValue: "COD King Powered WhatsApp" }),
      description:
        I18n.t("admin.cod_king_whatsapp_description", { defaultValue: "Order confirmation, fulfilment and abandoned-cart messages sent via COD King." }),
      enabled: codKingWhatsappEnabled,
      href: "/features/notifications",
    },
    {
      title: I18n.t("admin.branded_whatsapp", { defaultValue: "Business Brand WhatsApp" }),
      description:
        I18n.t("admin.branded_whatsapp_description", { defaultValue: "Send from your own verified WhatsApp Business number." }),
      enabled: brandedConnected,
      href: "/features/whatsapp",
    },
    {
      title: I18n.t("admin.broadcast_campaigns", { defaultValue: "Broadcast / Campaigns" }),
      description:
        I18n.t("admin.broadcast_campaigns_description", { defaultValue: "Run one-off broadcasts and scheduled WhatsApp campaigns." }),
      enabled: brandedConnected,
      href: "/features/whatsapp-campaigns",
    },
    {
      title: I18n.t("admin.inbound_webhooks", { defaultValue: "Inbound webhooks" }),
      description:
        I18n.t("admin.inbound_webhooks_description", { defaultValue: "Let Shopflo or another checkout platform push abandoned carts straight into your reminders." }),
      enabled: webhooksConnected,
      href: "/settings-hub/webhooks",
    },
  ];

  return (
    <SectionHub
      title={I18n.t("nav.messaging", { defaultValue: "SMS & WhatsApp" })}
      subtitle={
        I18n.t("admin.messaging_hub_subtitle", { defaultValue: "Manage customer notifications across SMS and WhatsApp." })
      }
      items={items}
      preview={
        brandedConnected ? (
          <Banner tone="success" title={I18n.t("admin.branded_active", { defaultValue: "Business Brand WhatsApp active" })}>
            {I18n.t("admin.branded_active_body", { defaultValue: "Messages send from your own WhatsApp Business number. Branded toggles are managed under Business Brand WhatsApp." })}
          </Banner>
        ) : (
          <Banner tone="info" title={I18n.t("admin.cod_king_powered", { defaultValue: "COD King powered" })}>
            {I18n.t("admin.cod_king_powered_body", { defaultValue: "Connect a Business Brand WhatsApp number to send from your own brand and unlock campaigns." })}
          </Banner>
        )
      }
    />
  );
};

export default MessagingHub;
