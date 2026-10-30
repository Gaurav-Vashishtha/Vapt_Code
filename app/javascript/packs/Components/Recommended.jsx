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
// import Fast from "../Assets/fast";

const scriptUrl = `http://${process.env.APP_HOST}/script.js`;

const scriptData = `<!-- COD King ${I18n.t("admin.starts")} -->
  <script>
    (function () {
      try {
        if (!window.Shopify.Checkout && !window.Shopify.checkout) return;
        document.body.style.opacity = 0;
        var script = document.createElement('script');
        script.src = '${scriptUrl}';
        script.async = false;
        var head = document.getElementsByTagName('head')[0];
        head.insertBefore(script, head.firstChild);
      } catch(e) {
        document.body.style.opacity = 1;
      }
    })();
  </script>
<!-- COD King ${I18n.t("admin.ends")} -->`;

const Recommended = () => {
  const {
    shop: [shop],
  } = useContext(StoreContext);
  const [copied, setCopied] = useState();
  // const [clipboard, // setClipboard] = useClippy();

  const copyToClipboard = () => {
    // setClipboard(scriptData);
    setCopied(true);
  };

  useEffect(() => {
    let timeout = "";
    if (copied) {
      timeout = setTimeout(() => {
        setCopied(false);
      }, 3000);
    }
    return () => clearTimeout(timeout);
  }, [copied, setTimeout, clearTimeout]);

  return (
    <>
      <FormLayout.Group>
        <CalloutCard
          title={I18n.t("recommended.reduce_time_to_load_otp_box")}
          illustration={"NA"}
          primaryAction={{
            primary: true,
            content: I18n.t("recommended.open_checkout_settings"),
            external: true,
            url: `https://${shop.shopify_domain}/admin/settings/checkout`,
          }}
          secondaryAction={{
            primary: false,
            content: I18n.t("recommended.watch_quick_video"),
            external: true,
            url: "https://github.com/amandeep009/resources/blob/0ff0920723a438b06165efdf27be7407f545810d/load_otp_fast.gif",
          }}
        >
          <p>
            <b>
              <u> {I18n.t("recommended.one_time_simple_steps")}</u>
            </b>
          </p>
          <p>
            {" "}
            {I18n.t("recommended.step_copy_script", {
              copy: I18n.t("recommended.copy"),
            })}{" "}
          </p>
          <p>
            {" "}
            {I18n.t("recommended.step_click_open_settings", {
              button: I18n.t("recommended.open_checkout_settings"),
            })}
          </p>
          <p>
            {" "}
            {I18n.t("recommended.step_paste_in_box", {
              box: I18n.t("recommended.additional_scripts_text_box"),
            })}
          </p>
          <p>
            {I18n.t("recommended.dont_see_the_script_box")}{" "}
            <b>
              <a
                href="https://codking.notion.site/Reenabling-the-additional-scripts-box-to-paste-COD-King-OTP-verification-Script-37b9331afa5946cfb141e51ad0e42ce4"
                target="_blank"
              >
                {I18n.t("recommended.enable_it_back")}{" "}
              </a>
            </b>
          </p>
          <p>
            {I18n.t("recommended.this_reduces_the_time_to_load")}
          </p>
        </CalloutCard>
        <Card
          sectioned
          title={I18n.t("recommended.copy_and_paste_the_below_script")}
          actions={[
            {
              content: I18n.t("recommended.where_to_paste_below_script"),
              external: true,
              url: "https://www.notion.so/codking/How-To-Setup-OTP-Verification-for-COD-Orders-d0969e70a7e8401da5e1f79e7e42648b?pvs=4#a24d8525dbd64070be6f04e7bd04e29a",
            },

            {
              content: I18n.t("recommended.learn_how_to_re_enable_the"),
              external: true,
              url: "https://codking.notion.site/Reenabling-the-additional-scripts-box-to-paste-COD-King-OTP-verification-Script-37b9331afa5946cfb141e51ad0e42ce4",
            },
          ]}
        >
          <pre
            style={{
              background: "#f5f5f5",
              padding: 15,
              lineHeight: 1,
              borderRadius: 3,
              display: "inline-block",
              position: "relative",
              wordWrap: "break-word",
              maxWidth: "100%",
              overflowY: "hidden",
            }}
          >
            {scriptData}
            <div style={{ position: "absolute", right: 0, bottom: 0 }}>
              <Button variant="primary" onClick={copyToClipboard} disabled={copied}>
                {copied ? I18n.t("admin.copied") : I18n.t("admin.copy")}
              </Button>
            </div>
          </pre>
          {/* <Link external onClick={() => window.$crisp.push(["do", "chat:open"])}>Get free help from our expert - Chat with us Now</Link> */}
        </Card>
      </FormLayout.Group>
    </>
  );
};

export default Recommended;
