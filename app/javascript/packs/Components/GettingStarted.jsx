import React, {useContext} from "react";
import { Banner, Button } from "@shopify/polaris";
import I18n from '../i18n-lang'
import { StoreContext } from "../Context/Store";
import { navigateTo } from "../../utils/navigate";

const GettingStarted = () => {
  const {
    crispUrl: [crispUrl],
  } = useContext(StoreContext);
  return (
    <div style={{ marginTop: "20px", marginBottom: "20px" }}>
      <Banner status="info" title={I18n.t('admin.getting_started')}>
        <p style={{ marginBottom: "10px" }}>
          {I18n.t('admin.watch_video_msg')}
        </p>
        <div style={{ display: "flex", flexDirection: "row" }}>
          <div>
            <Button
              variant="primary"
              onClick={() => {
                window.open(
                  "https://www.youtube.com/watch?v=yqmAL9G47Iw",
                  "_blank"
                );
              }}
            >
              {I18n.t('admin.watch_video')}
            </Button>
          </div>
          <div style={{ marginLeft: 20 }}>
            <Button
              variant="primary"
              onClick={() => {
                navigateTo("/help-and-support");
              }}
            >
              {I18n.t("callback.request_button", { defaultValue: "Schedule callback" })}
            </Button>
          </div>
          <div style={{ marginLeft: 20 }}>
            <Button
              variant="primary"
              onClick={() => {
                if (navigator.cookieEnabled) {
                  window.$crisp.push(["do", "chat:open"]);
                } else {
                  window.open(crispUrl, '_blank')
                }
              }}
            >
              {I18n.t('admin.chat_with_us')}
            </Button>
          </div>
        </div>
      </Banner>
    </div>
  );
};

export default GettingStarted;
