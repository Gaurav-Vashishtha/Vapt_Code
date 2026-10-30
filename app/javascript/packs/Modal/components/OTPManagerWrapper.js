import React, { useState, useEffect } from "react";
import OTPManager from "./OTPManager";
import { debugLog } from "../utilities/otpUtils";

const OTPManagerWrapper = (props) => {
  // Use a key that changes to force a full remount
  const [otpKey, setOtpKey] = useState(Date.now());

  useEffect(() => {
    const handlePageShow = (event) => {
      debugLog("pageshow event in wrapper fired:", event);
      if (event.persisted) {
        debugLog("Page restored from bfcache. Forcing OTPManager remount.");
        setOtpKey(Date.now());
      }
    };

    window.addEventListener("pageshow", handlePageShow);
    debugLog("pageshow event listener added in OTPManagerWrapper");

    return () => {
      window.removeEventListener("pageshow", handlePageShow);
      debugLog("pageshow event listener removed in OTPManagerWrapper");
    };
  }, []);

  return <OTPManager key={otpKey} {...props} />;
};

export default OTPManagerWrapper;
