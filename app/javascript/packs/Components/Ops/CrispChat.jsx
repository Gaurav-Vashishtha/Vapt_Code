import React, { useEffect } from 'react';
import CryptoJS from 'crypto-js';

const CrispChat = ({ shop, plan }) => {
  useEffect(() => {
    // Include the Crisp code here, without the <script></script> tags
    window.$crisp = [];
    window.CRISP_WEBSITE_ID = process.env.CRISP_WEBSITE_ID;
    window.CRISP_RUNTIME_CONFIG = {
      session_merge : false
    };

    (function() {
      var d = document;
      var s = d.createElement('script');

      s.src = 'https://client.crisp.chat/l.js';
      s.async = 1;
      d.getElementsByTagName('head')[0].appendChild(s);
    })();
  }, []);

  // Crisp is shown on all viewports in the admin panel (including mobile).
  // Previously hidden on mobile to avoid blocking taps in embedded storefront views.
  useEffect(() => {
    document.body.classList.remove("codking-mobile-chat-hidden");
    window.$crisp?.push(["do", "chat:show"]);
    return () => document.body.classList.remove("codking-mobile-chat-hidden");
  }, []);

  useEffect(() => {
    if (window.CRISP_WEBSITE_ID) {
      if (shop?.shop_owner) {
        window.$crisp.push(['set', 'user:nickname', shop.shop_owner])
      }
      if (shop?.id) {
        $crisp.push(["set", "session:data", ["Shop_Admin_Link",  `https://app.codking.tech/admin/shops/${shop.id}`]]);
        $crisp.push(["set", "session:data", ["app", 'cod']]);
      }
      if (shop?.owner_email) {
        window.$crisp.push(['set', 'user:email', shop.owner_email])
      }
      if (shop?.owner_phone) {
        window.$crisp.push(["set", "user:phone", shop.owner_phone.replace(/\D/g,'')])
      }
      if (shop?.shopify_domain) {
        window.CRISP_TOKEN_ID = CryptoJS.MD5(shop.shopify_domain).toString();
        $crisp.push(['set', 'session:data', ['clarity', `https://clarity.microsoft.com/projects/view/jzg5x3cznq/impressions?CustomUserId=${shop.shopify_domain}`]])
      }
      if (plan?.name) {
        $crisp.push(["set", "session:data", ["plan", plan.name]]);
      }
      if (plan?.price) {
        $crisp.push(["set", "session:data", ["price", String(plan.price)]]);
      }
      if (shop?.shopify_domain) {
        $crisp.push(["set", "session:data", ["shopify_domain", shop.primary_domain.presence || shop.shopify_domain]]);
        $crisp.push(["set", "session:data", ["app", 'cod']]);
      }

      if (shop?.charge_id) {
        $crisp.push(["set", "session:data", ["charge_id", shop.charge_id]]);
        $crisp.push(["set", "session:data", ["app", 'cod']]);
      }
      if (shop?.shopify_plan) {
        $crisp.push(["set", "session:data", ["shopify_plan", shop.shopify_plan]]);
        $crisp.push(["set", "session:data", ["app", 'cod']]);
      }
      if (shop?.created_at) {
        $crisp.push(["set", "session:data", ["Installed_On", shop.created_at]]);
        $crisp.push(["set", "session:data", ["app", 'cod']]);
      }
      if (shop?.shop_created_date) {
        $crisp.push(["set", "session:data", ["Shop_Created_On", shop.shop_created_date]]);
        $crisp.push(["set", "session:data", ["app", 'cod']]);
      }
      
    }
  }, [shop, plan, window.CRISP_WEBSITE_ID]);

  return null
}

export default CrispChat