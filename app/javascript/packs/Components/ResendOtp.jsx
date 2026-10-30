import React, { useState } from "react";
import I18n from "../i18n-lang";
import useInterval from "@use-it/interval";
import useAxios from "axios-hooks";

const ResendOtp = ({ orderId, phone, settings }) => {
  const defaultWaitTime = settings.otpWaitTime
    ? settings.otpWaitTime * 1000
    : 30000;
  const [waitTime, setWaitTime] = useState(defaultWaitTime);
  const [retries, setRetries] = useState(settings.maxRetries || 5);

  const [{ loading: resendLoading }, resendOtp] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/order_confirmations/update_ph_and_send_otp`,
      method: "POST",
    },
    { manual: true },
  );

  useInterval(
    () => {
      setWaitTime((w) => w - 1000);
    },
    waitTime ? 1000 : null,
  );

  const onResend = () => {
    setRetries((r) => r - 1);
    if (waitTime < 1) {
      setWaitTime(defaultWaitTime);
      resendOtp({
        data: {
          order_id: orderId,
          customer_number: phone,
        },
      });
      // onResendOtp()
    }
  };

  const ResendText = (
    <span style={{ color: settings.id == 2427 ? "black" : "" }}>
      {I18n.t("script.resend_in_x_seconds", {
        count: waitTime / 1000,
      })}
    </span>
  );

  const ResendLink = (
    <button
      type="button"
      className="link--small"
      onClick={onResend}
      style={{
        cursor: "pointer",
        color: settings.id == 2427 ? "black" : "",
        background: "none",
        border: 0,
        padding: 0,
      }}
    >
      {I18n.t("script.resend_otp")}
    </button>
  );

  if (resendLoading) {
    return I18n.t("script.sending");
  }

  if (retries < 1) {
    return <span>{I18n.t("script.max_retries_reached")}</span>;
  }

  return <>{waitTime > 0 ? ResendText : ResendLink}</>;
};

export default ResendOtp;
