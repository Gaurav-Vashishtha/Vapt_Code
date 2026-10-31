import React, { useState, useCallback, useRef, useEffect } from "react";
import "./application.css";
import useAxios from "axios-hooks";
import CountryCode from "./CountryCode";
import {
  debugLog,
  getSessionValue,
  setSessionValue,
} from "../Modal/utilities/otpUtils";
import { emitShopifyVisitorIdentify } from "../Modal/utilities/shopifyVisitor";
import I18n from "../i18n-lang";

const CodkOTPWidget = ({ enableCheckOutFn, disableCheckoutFn }) => {
  const inputRef = useRef(null);

  const [otp, setOtp] = useState("");
  const [mode, setMode] = useState("SMS");

  const onOtpChange = (e) => {
    if (Number.isInteger(Number(e.target.value))) {
      setOtp(e.target.value);
    }
  };

  const MAX_TRY_PHONE_NO_CHANGE = 3;
  const SERVER_ERROR_TEXT =
    "Too many attemps. Please select other payment options.";
  const WRONG_PHONE_TEXT = "Invalid mobile number.";
  const WRONG_CALLING_COUNTRY_CODE_TEXT = "Wrong country code.";
  const DID_NOT_RECEIVE_OTP_TEXT = "Didn't receive the Code?";
  const CHANGE_LINK_TEXT = "Change";
  const RESEND_LINK_TEXT = "Resend";

  const [wrongOtpText, setWrongOtpText] = useState("Wrong OTP.");
  const [verifyBtnText, setVerifyBtnText] = useState("Verify");
  const [heading, setHeading] = useState("Login/Signup to Checkout");
  const [subHeading, setSubHeading] = useState(
    "Confirm your mobile number to proceed to checkout"
  );
  const [sendBtnText, setSendBtnText] = useState("Send Code");
  const [skipBtnText, setSkipBtnText] = useState("Skip to place Non-COD order");
  const [redirectText, setRedirectText] = useState(
    "Verified - You will be redirected to checkout page in a few seconds."
  );
  const [showSkipBtn, setShowSkipBtn] = useState(false);

  const OTP_SENT_TEXT = "Code was sent to";

  const CODK_MAX_RETRY_TEXT = "Maximum retry limit reached";
  const CODK_OTP_CARD_CLASS_DEFAULT = "codk-otpw-container";
  const SLIDE_LEFT_CLASS = "codk-slide-left";
  const SLIDE_RIGHT_CLASS = "codk-slide-right";
  const CODK_OTP_VERIFY_CARD_CLASS = "codk-otpw-verify-card";
  const CODK_OTP_VERIFY_CARD_WRAPPER_CLASS = "codk-otpw-verify-card-warapper";
  const CODK_OTP_WRAPPER_CLASS = "codk-otpw-otp";

  const CODK_OTP_VERIFY_BTN_WRAPPER_CLASS = "codk-otpw-verify";
  const CODK_OTP_VERIFY_BTN_CLASS = "codk-otpw-verify-btn-div";

  const [isOtpEnabledFromBackend, setIsOtpEnabledFromBackend] = useState(false);
  const [enablePreOrderOtp, setEnablePreOrderOtp] = useState(false);

  const [showCodKPhone, setShowCodKPhone] = useState(true);
  const [showCodKVerify, setShowCodKVerify] = useState(false);
  const [showCodKSendLoader, setShowCodKSendLoader] = useState(false);
  const [showCodKVerifyLoader, setShowCodKVerifyLoader] = useState(false);
  const [showWrongPhoneNoText, setShowWrongPhoneNoText] = useState(false);
  const [showWrongCountryCodeText, setShowWrongCountryCodeText] =
    useState(false);
  const [showVerifyToCheckout, setShowVerifyToCheckout] = useState(true);
  const [phoneNoChangeCounter, setPhoneNoChangeCounter] = useState(0);

  const [phoneNumber, setPhoneNumber] = useState("");
  const [countryCallingCode, setCountryCallingCode] = useState("+");
  const [codkOTPCardClass, setCodkOTPCardClass] = useState(
    "codk-otpw-container"
  );

  const verifyBtnRef = useRef(null);

  const [prePrimaryButtonColor, setPrePrimaryButtonColor] = useState("#000000");
  const [preSecondaryButtonColor, setPreSecondaryButtonColor] =
    useState("#000000");

  const [prePrimaryButtonFontColor, setPrePrimaryButtonFontColor] =
    useState("#FFFFFF");
  const [preSecondaryButtonFontColor, setPreSecondaryButtonFontColor] =
    useState("#FFFFFF");

  const [preWhatsappButton, setPreWhatsappButton] = useState(false);
  const [preWhatsappButtonText, setPreWhatsappButtonText] = useState(
    "Send Code to Whatsapp"
  );

  const [ip, setIp] = useState("");
  const [countryCode, setCountryCode] = useState("");

  const [showWrongOtpText, setShowWrongOtpText] = useState(false);
  const [showServerErrorText, setShowServerErrorText] = useState(false);
  const [showErrorSendingOTP, setErrorSendingOTP] = useState(false);

  const [showOtpSentText, setShowOtpSentText] = useState(false);
  const [showDidNotReceiveOtpText, setShowDidNotReceiveOtpText] =
    useState(true);
  const [showCodKVerified, setShowCodKVerified] = useState(false);
  const [showResendLink, setShowResendLink] = useState(true);
  const [showResendTimer, setShowResendTimer] = useState(false);
  const [showMaxRetryLimitReachedTxt, setShowMaxRetryLimitReachedTxt] =
    useState(false);
  const [timer, setTimer] = useState(0);
  const [otpWaitTimeInCodKSettings, setOtpWaitTimeInCodKSettings] = useState(0);
  const [maxTriesInCodKSettings, setMaxTriesInCodKSettings] = useState(0);
  const [callingCodeList, setCallingCodeList] = useState([]);

  const populateCallingCodeList = (text) => {
    const countryCallingCodeArray = text.split(",");
    let result = [];
    countryCallingCodeArray.forEach((item, index) => {
      const filterCountry = CountryCode.filter(
        (country) => country.value == item
      );
      if (filterCountry && filterCountry.length > 0) {
        result.push({
          name: filterCountry[0].value,
          value: filterCountry[0].label,
        });
      }
    });
    setCallingCodeList(result);
    setCountryCallingCode(result[0].value);
    setCountryCode(result[0].name);
  };

  const resetTimer = (forceReset = false) => {
    const timerSizeInSeconds = otpWaitTimeInCodKSettings
      ? otpWaitTimeInCodKSettings
      : 60;
    if (!timer) {
      setTimer(timerSizeInSeconds);
    }
    if (forceReset) {
      setTimer(timerSizeInSeconds);
    }
  };

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    if (showCodKVerify) {
      timer > 0 && setTimeout(timeOutCallback, 1000);
    }
  }, [showCodKVerify, timer]);

  useEffect(() => {
    if (showCodKVerify) {
      setPhoneNoChangeCounter(phoneNoChangeCounter + 1);
    }
  }, [showCodKVerify]);

  useEffect(() => {
    if (!showCodKPhone) {
      resetTimer(true);
    }
  }, [showCodKPhone]);

  const timeOutCallback = useCallback(() => {
    setTimer((currTimer) => {
      if (currTimer === 1) {
        setShowResendTimer(false);
        setShowResendLink(true);
      }
      return currTimer - 1;
    });
  }, []);

  function uuidv4() {
    // CSPRNG-backed v4; Math.random() is predictable once a few outputs leak.
    const rng =
      typeof globalThis !== "undefined" && globalThis.crypto ? globalThis.crypto : null;
    if (rng && typeof rng.randomUUID === "function") return rng.randomUUID();
    if (rng && typeof rng.getRandomValues === "function") {
      const bytes = new Uint8Array(16);
      rng.getRandomValues(bytes);
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0"));
      return `${hex.slice(0,4).join("")}-${hex.slice(4,6).join("")}-${hex.slice(6,8).join("")}-${hex.slice(8,10).join("")}-${hex.slice(10,16).join("")}`;
    }
    throw new Error("Secure random source unavailable; cannot generate id");
  }

  function getMachineId() {
    let machineId = getSessionValue("MachineId");
    if (!machineId) {
      machineId = uuidv4();
      setSessionValue("MachineId", machineId);
    }
    return machineId;
  }

  const [
    { data: postData, loading: putLoading, error: postError },
    executePost,
  ] = useAxios(
    {
      url: `${window.Shopify.routes.root}cart/update.js`,
      method: "POST",
    },
    { manual: true }
  );

  const [
    { data: postLineData, loading: putLineLoading, error: postLineError },
    executeLinePost,
  ] = useAxios(
    {
      url: `${window.Shopify.routes.root}cart/change.js`,
      method: "POST",
    },
    { manual: true }
  );

  const [{ loading: loadingGetCartAttr }, getCartAttributes] = useAxios(
    {
      url: `${window.Shopify.routes.root}cart.js`,
      method: "GET",
    },
    { manual: true }
  );

  const [{ loading: loadingFetchMachineDetails }, fetchMachineDetails] =
    useAxios(
      {
        url: "https://ipapi.co/json/",
        method: "GET",
      },
      { manual: true }
    );

  const [{ loading: loadingFetchSettings }, fetchSettings] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/script/settings?domain=${window.Shopify.shop}`,
      method: "GET",
    },
    { manual: true }
  );

  const [{ loading: loadingSend }, sendApiCall] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/order_confirmations/pre_order_otp`,
      method: "POST",
      data: {
        country_code: countryCode,
        phone: (countryCallingCode + phoneNumber).replace("+", ""),
        ip_address: ip,
        device_id: getMachineId(),
        shop: window.Shopify.shop,
        mode: "SMS",
      },
    },
    { manual: true }
  );

  const [{ loading: loadin2gSend }, sendApiCallWhatsapp] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/order_confirmations/pre_order_otp`,
      method: "POST",
      data: {
        country_code: countryCode,
        phone: (countryCallingCode + phoneNumber).replace("+", ""),
        ip_address: ip,
        device_id: getMachineId(),
        shop: window.Shopify.shop,
        mode: "WHATSAPP",
      },
    },
    { manual: true }
  );

  const [{ loading: loadingVerify }, verifyApiCall] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/order_confirmations/pre_order_otp_verify`,
      method: "POST",
      data: {
        country_code: countryCode,
        phone: (countryCallingCode + phoneNumber).replace("+", ""),
        ip_address: ip,
        device_id: getMachineId(),
        shop: window.Shopify.shop,
        otp: otp,
      },
    },
    { manual: true }
  );

  useEffect(() => {
    ///=== API CALL START ===///
    fetchSettings()
      .then((response) => {
        if (response.status === 200) {
          debugLog("FetchSettings1");
          const maxTries = response.data.max_retries
            ? response.data.max_retries
            : 5;
          const enable_pre_order_otp = response?.data?.enable_pre_order_otp;
          setEnablePreOrderOtp(enable_pre_order_otp);
          setOtpWaitTimeInCodKSettings(response.data.otp_wait_time);
          setMaxTriesInCodKSettings(maxTries);
          populateCallingCodeList(response.data.country_code_list);

          setWrongOtpText(response.data.pre_invalid_otp_msg);
          setVerifyBtnText(response.data.pre_verify_button_label);
          setHeading(response.data.pre_heading);
          setSubHeading(response.data.pre_sub_heading);
          setSendBtnText(response.data.pre_send_button_label);
          setSkipBtnText(response.data.pre_skip_btn_text);
          setRedirectText(response.data.pre_redirect_text);
          setShowSkipBtn(response.data.pre_show_skip_btn);
          setPrePrimaryButtonColor(response.data.pre_primary_button_color);
          setPreSecondaryButtonColor(response.data.pre_secondary_button_color);
          setPrePrimaryButtonFontColor(
            response.data.pre_primary_button_font_color
          );
          setPreSecondaryButtonFontColor(
            response.data.pre_secondary_button_font_color
          );

          setPreWhatsappButton(response.data.pre_whatsapp_button);
          setPreWhatsappButtonText(response.data.pre_whatsapp_button_text);

          debugLog("FetchSettings Complete");

          if (enable_pre_order_otp && enable_pre_order_otp !== true) {
            debugLog("55555X");
            enableCheckOutFn();
            return;
          }
          if (maxTries > 0) {
            setShowMaxRetryLimitReachedTxt(false);
          }

          setIsOtpEnabledFromBackend(enable_pre_order_otp);
          if (!response.data.enable_pre_order_otp == false) {
            return;
          }
        } else {
          setEnablePreOrderOtp(false);
          return;
        }
      })
      .catch((e) => {
        debugLog("FetchSettings22");
        setEnablePreOrderOtp(false);
        return;
      });
    ///=== API CALL END ===///

    fetchMachineDetails()
      .then((response) => {
        let data = response?.data;
        if (response.status === 200 && data) {
          setIp(data.ip);
        }
      })
      .catch((e) => {
        debugLog("FetchSettings33");
      });
    ///=== API CALL END ===///

    ///=== API CALL START ===///
    getCartAttributes()
      .then((resp) => {
        if (resp.status === 200) {
          debugLog("FetchSettings66");
          if (resp.data.attributes.isCodkOtpVerifed) {
            const codkCartOtpVerifiedPhoneNo =
              resp.data.attributes.codkCartOtpVerifiedPhoneNo;
            setPhoneNumber(
              codkCartOtpVerifiedPhoneNo.substring(
                codkCartOtpVerifiedPhoneNo.length - 10
              )
            );
            setShowCodKVerified(true);
          } else {
            setShowCodKVerified(false);
          }
        } else {
          setShowCodKVerified(false);
        }
      })
      .catch((e) => {
        debugLog("FetchSettings44");
        setShowCodKVerified(false);
      });
    ///=== API CALL END ===///
  }, []);

  const addCartAttribute = (codkCartOtpVerifiedPhoneNo, isCodkOtpVerifed) => {
    ///=== API CALL START ===///
    executePost({
      data: {
        attributes: {
          _otpVerifiedPhoneNumber: codkCartOtpVerifiedPhoneNo,
        },
      },
    })
      .then((resp) => {
        if (resp.status === 200) {
          debugLog("Cart attribute added..Adding line attribute");
          addLineAttribute(
            codkCartOtpVerifiedPhoneNo,
            isCodkOtpVerifed,
            resp.data
          );
        } else {
          debugLog("Error adding cart attribute");
        }
      })
      .catch((e) => {
        debugLog("Error1 adding cart attribute" + e);
      });
    ///=== API CALL END ===///
  };

  const addLineAttribute = (
    codkCartOtpVerifiedPhoneNo,
    isCodkOtpVerifed,
    attrsResp
  ) => {
    ///=== API CALL START ===///
    //const newProperties = Object.assign({}, attrsResp.items[attrsResp.items.findIndex(item => !item.gift_card)].properties, { 'isCodkOtpVerifed': isCodkOtpVerifed,'codkCartOtpVerifiedPhoneNo':codkCartOtpVerifiedPhoneNo });
    const newProperties = {
      _otpVerifiedPhoneNumber: codkCartOtpVerifiedPhoneNo,
    };
    const payload = {
      line: attrsResp.items.findIndex((item) => !item.gift_card) + 1,
      quantity: attrsResp.items[0]?.quantity,
      properties: {
        ...attrsResp.items[0]?.properties,
        _otpVerifiedPhoneNumber: codkCartOtpVerifiedPhoneNo,
      },
    };
    executeLinePost({
      data: payload,
    })
      .then((resp) => {
        if (resp.status === 200) {
          debugLog("Line attribute added..");
          emitShopifyVisitorIdentify({
            phone: codkCartOtpVerifiedPhoneNo,
            email: getSessionValue("customer-email"),
            countryCallingCode,
          });
          setShowCodKVerify(false);
          setTimeout(function () {
            window.location.href = "/checkout";
          }, 1500);
        } else {
          debugLog("Error adding line attribute");
        }
      })
      .catch((e) => {
        debugLog("Error12 adding line attribute" + e);
      });
    ///=== API CALL END ===///
  };

  const getCountryCode = (countryCallingCode) => {
    //+91
    const filterCountry = CountryCode.filter(
      (country) => country.label == countryCallingCode
    );
    return filterCountry[0].value;
  };

  const onCountryCallingCodeChange = useCallback(
    (e) => {
      //+91
      let countryCallingCode = e.target.value;
      setCountryCallingCode(countryCallingCode);
      //IN
      let countryCode = getCountryCode(countryCallingCode);
      setCountryCode(countryCode);
    },
    [countryCallingCode]
  );

  const isValidNumber = (text) => {
    const re = /^[0-9\b]+$/;
    return re.test(text);
  };

  const onPhoneNumberChange = useCallback(
    (e) => {
      let phoneNo = e.target.value;
      if (
        (phoneNo.length <= 10 && isValidNumber(phoneNo)) ||
        phoneNo.length === 0
      ) {
        setPhoneNumber(phoneNo.replace(/^0+/, ""));
      }
    },
    [phoneNumber]
  );

  const onModeChange = useCallback(
    (mode) => {
      setMode(mode);
    },
    [mode]
  );

  const isMaxRetryDone = () => {
    return !maxTriesInCodKSettings > 0;
  };

  const onSkipButtonClick = (e) => {
    window.location = "/checkout";
  };
  const onSendBtnClick = (event, mode) => {
    onModeChange(mode);
    if (!isCallingCodeValid(countryCallingCode)) {
      setShowWrongCountryCodeText(true);
      setShowWrongPhoneNoText(false);
      return;
    }

    if (!(phoneNumber.length >= 8) || !isValidNumber(phoneNumber)) {
      setShowWrongPhoneNoText(true);
      setShowWrongCountryCodeText(false);
      return;
    }
    let countryCode = getCountryCode(countryCallingCode);
    //setCountryCode(countryCode);
    setShowWrongPhoneNoText(false);
    setShowWrongCountryCodeText(false);
    setShowServerErrorText(false);
    setShowWrongOtpText(false);
    setErrorSendingOTP(false);
    if (isMaxRetryDone() || phoneNoChangeCounter === MAX_TRY_PHONE_NO_CHANGE) {
      setShowVerifyToCheckout(false);
      setShowMaxRetryLimitReachedTxt(true);
      setShowCodKVerify;
      setShowResendTimer(false);
      return;
    }
    if (!(phoneNumber.length >= 8) || !isValidNumber(phoneNumber)) {
      setShowWrongPhoneNoText(true);
      setShowWrongCountryCodeText(false);
    } else if (!isCallingCodeValid(countryCallingCode)) {
      setShowWrongCountryCodeText(true);
      setShowWrongPhoneNoText(false);
    } else if (
      phoneNumber.length >= 8 &&
      isValidNumber(phoneNumber) &&
      isCallingCodeValid(countryCallingCode)
    ) {
      setShowCodKSendLoader(true);
      ///=== API CALL START ===///
      if (mode == "WHATSAPP") {
        sendApiCallWhatsapp()
          .then((resp) => {
            setShowCodKSendLoader(false);
            if (resp.status === 200 && resp.data.status === "Success") {
              setMaxTriesInCodKSettings(maxTriesInCodKSettings - 1);
              setCodkOTPCardClass(
                `${CODK_OTP_CARD_CLASS_DEFAULT} ${SLIDE_LEFT_CLASS}`
              );
              setShowCodKVerify(true);
              setShowCodKPhone(false);
              setShowOtpSentText(true);
              setErrorSendingOTP(false);
              setShowServerErrorText(false);
              //codkOtpInput1Ref.current.focus();
            } else {
              setErrorSendingOTP(true);
              setShowOtpSentText(false);
              setShowServerErrorText(false);
            }
          })
          .catch((e) => {
            setShowCodKSendLoader(false);
            setShowOtpSentText(false);
            setShowServerErrorText(true);
          })
          .finally(() => {
            setShowResendTimer(true);
            setShowResendLink(false);
            setShowCodKSendLoader(false);
          });
      } else {
        sendApiCall()
          .then((resp) => {
            setShowCodKSendLoader(false);
            if (resp.status === 200 && resp.data.status === "Success") {
              setMaxTriesInCodKSettings(maxTriesInCodKSettings - 1);
              setCodkOTPCardClass(
                `${CODK_OTP_CARD_CLASS_DEFAULT} ${SLIDE_LEFT_CLASS}`
              );
              setShowCodKVerify(true);
              setShowCodKPhone(false);
              setShowOtpSentText(true);
              setShowServerErrorText(false);
              setErrorSendingOTP(false);
              //codkOtpInput1Ref.current.focus();
            } else {
              setShowOtpSentText(false);
              setShowServerErrorText(false);
              setErrorSendingOTP(true);
            }
          })
          .catch((e) => {
            setShowCodKSendLoader(false);
            setShowOtpSentText(false);
            setShowServerErrorText(true);
          })
          .finally(() => {
            setShowResendTimer(true);
            setShowResendLink(false);
            setShowCodKSendLoader(false);
          });
      }
    }
  };

  const onFormSubmit = (e) => {
    debugLog("Submitted");
    e.preventDefault();

    if (showCodKVerify) {
      onVerifyBtnClick(e);
    } else {
      debugLog("abbbcdjjj");
      onSendBtnClick(e, "SMS");
    }
  };

  const onVerifyBtnClick = (e) => {
    setShowWrongOtpText(false);
    setShowServerErrorText(false);
    setErrorSendingOTP(false);
    if (otp.toString().length === 4 && isValidNumber(otp)) {
      setShowCodKVerifyLoader(true);
      ///=== API CALL START ===///
      verifyApiCall()
        .then((resp) => {
          if (resp.status === 200 && resp.data.verification) {
            setShowCodKVerified(true);
            setShowCodKPhone(true);
            addCartAttribute(
              (countryCallingCode + phoneNumber).replace("+", ""),
              resp.data.verification
            );
            // setTimeout(function () {
            //     window.location.href = "/checkout";
            //  }, 2000);
          } else {
            setShowWrongOtpText(true);
            setShowServerErrorText(false);
            setErrorSendingOTP(false);
          }
          setShowCodKVerifyLoader(false);
        })
        .catch((e) => {
          setShowWrongOtpText(false);
          setShowServerErrorText(true);
          setShowCodKVerifyLoader(false);
        })
        .finally(() => {
          setShowCodKVerifyLoader(false);
        });
      ///=== API CALL END ===///
    } else {
      setShowWrongOtpText(true);
      setShowServerErrorText(false);
      setErrorSendingOTP(false);
    }
  };

  const onChangePhonNoBtnClick = (e) => {
    setPhoneNumber("");
    setShowCodKVerify(false);
    setShowCodKPhone(true);
    setCodkOTPCardClass(`${CODK_OTP_CARD_CLASS_DEFAULT} ${SLIDE_RIGHT_CLASS}`);
  };

  const onResendOtpBtnClick = (e) => {
    if (isMaxRetryDone()) {
      setShowVerifyToCheckout(false);
      setShowResendLink(true);
      setShowResendTimer(false);
      setShowMaxRetryLimitReachedTxt(true);
      setShowWrongOtpText(false);
      return;
    }
    setShowResendTimer(true);
    setShowResendLink(false);
    debugLog("jjjjjj");
    onSendBtnClick(e, "SMS");
    setShowWrongOtpText(false);
    resetTimer(true);
  };

  const isCallingCodeValid = (text) => {
    return (
      text.charAt(0) === "+" && text.length >= 2 && !isNaN(text.substring(1))
    );
  };

  const domain =
    window.Shopify.shop == "shopelinph.myshopify.com" ||
    window.Shopify.shop == "seektheuniq.myshopify.com";

  return (
    <>
      <meta
        content={I18n.t("cart_otp_widget.width_device_width_initial_scale_1")}
        name="viewport"
      />
      <form onSubmit={onFormSubmit}>
        {enablePreOrderOtp && (showCodKPhone || showCodKVerify) && (
          <div className={codkOTPCardClass}>
            <div className="codk-otpw-header">
              {domain && (
                <div>
                  {window.Shopify.shop == "shopelinph.myshopify.com" && (
                    <img
                      src="https://elin.ph/cdn/shop/files/Elin_logo_new_copy1_copy_633f5934-4434-4a59-9bfe-f9e8f2acbd68.png?v=1614824657"
                      alt={I18n.t("cart_otp_widget.logo_for_elin")}
                      width="80"
                      height="auto"
                    />
                  )}
                  {window.Shopify.shop == "seektheuniq.myshopify.com" && (
                    <img
                      src="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/ezgif-4-7303841246.jpg?v=1697096619"
                      alt={I18n.t("cart_otp_widget.logo_for_seek_the_uniq")}
                      width="80"
                      height="auto"
                    />
                  )}
                </div>
              )}
              <span>{heading}</span>
              {/* {
                            (showCodKVerified) &&
                            <span className='codk-otpw-verified-txt'>Verified - You will be redirected now.</span>
                        } */}
              {showVerifyToCheckout &&
                (showCodKPhone || showCodKVerify) &&
                !showCodKVerified && (
                  <div className="codk-otpw-verify-now codk-blink-me">
                    {subHeading}
                  </div>
                )}
              {showCodKVerified && (
                <div className="codk-otpw-verified-proceed">{redirectText}</div>
              )}

              {showMaxRetryLimitReachedTxt && (
                <div className="codk-blink-me-red">{CODK_MAX_RETRY_TEXT}</div>
              )}
            </div>

            {showCodKPhone && (
              <div
                {...((showCodKVerified || showMaxRetryLimitReachedTxt) && {
                  disabled: true,
                })}
                className="codk-otpw-phone-card-wrapper"
              >
                <div style={{ padding: 10 }}>
                  <div
                    // className='codk-otpw-phone-card'
                    className="enter_phone"
                  >
                    <div
                    // className='codk-otpw-country-code'
                    >
                      <select
                        name="codk-otpw-country-code"
                        value={countryCallingCode}
                        className="country_code_select"
                        onChange={onCountryCallingCodeChange}
                        {...((showCodKVerified ||
                          showMaxRetryLimitReachedTxt) && { disabled: true })}
                      >
                        {/* <option value={''}>{'select'}</option> */}
                        {callingCodeList.map((e, key) => {
                          return (
                            <option key={key} value={e.value}>
                              {e.value}
                            </option>
                          );
                        })}
                      </select>
                    </div>
                    {/* <div className='codk-otpw-phone'> */}
                    {/* <input
                                        className='codk-otpw-phone-input'
                                        type="text"
                                        name="phoneNumber"
                                        placeholder="Enter Phone no."
                                        value={phoneNumber}
                                        onChange={onPhoneNumberChange}
                                        {...((showCodKVerified || showMaxRetryLimitReachedTxt) && { disabled: true })}
                                        inputMode='numeric' pattern="[0-9]*"
                                    /> */}

                    <input
                      className="eosh_ph_field_item eosh-phone-number"
                      type="tel"
                      id="phone-number"
                      placeholder={I18n.t("cart_otp_widget.enter_mobile_number")}
                      value={phoneNumber}
                      onChange={onPhoneNumberChange}
                      {...((showCodKVerified ||
                        showMaxRetryLimitReachedTxt) && { disabled: true })}
                      inputMode="numeric"
                      pattern="[0-9]*"
                    />

                    {/* </div> */}
                  </div>
                </div>
                <div className="codk-otpw-phone-msg-container">
                  <div className="codk-otpw-wrong-phone-msg-wrapper">
                    <div className="codk-otpw-wrong-phone-msg">
                      {showWrongPhoneNoText && WRONG_PHONE_TEXT}
                      {showWrongCountryCodeText &&
                        WRONG_CALLING_COUNTRY_CODE_TEXT}
                      {showServerErrorText && SERVER_ERROR_TEXT}
                      {showErrorSendingOTP &&
                        "OTP is not available. Please select other payment options that dont require OTP verification."}
                    </div>
                  </div>
                </div>
                <div style={{ padding: 10 }}>
                  <div
                    // className='codk-otpw-send'
                    onClick={(event) => onSendBtnClick(event, "SMS")}
                    {...((showCodKVerified || showMaxRetryLimitReachedTxt) && {
                      disabled: true,
                    })}
                  >
                    <div
                      style={{
                        backgroundColor: prePrimaryButtonColor,
                        margin: "0px",
                        borderRadius: "5px",
                        textAlign: "center",
                        width: "100%",
                        padding: "10px",
                        marginBottom: "0px",
                        lineHeight: "28pt",
                        color: prePrimaryButtonFontColor,
                        display: "block",
                        outline: "none",
                        cursor: "pointer",
                        fontSize: "14pt",
                      }}
                      {...((showCodKVerified ||
                        showMaxRetryLimitReachedTxt) && { disabled: true })}
                    >
                      {sendBtnText}
                    </div>
                  </div>
                </div>
                {preWhatsappButton && (
                  <div style={{ padding: 10 }}>
                    <div
                      // className='codk-otpw-send'
                      onClick={(event) => onSendBtnClick(event, "WHATSAPP")}
                      {...((showCodKVerified ||
                        showMaxRetryLimitReachedTxt) && { disabled: true })}
                    >
                      <div
                        style={{
                          backgroundColor: prePrimaryButtonColor,
                          margin: "0px",
                          borderRadius: "5px",
                          textAlign: "center",
                          width: "100%",
                          padding: "10px",
                          marginBottom: "0px",
                          lineHeight: "28pt",
                          color: prePrimaryButtonFontColor,
                          display: "block",
                          outline: "none",
                          cursor: "pointer",
                          fontSize: "14pt",
                        }}
                        {...((showCodKVerified ||
                          showMaxRetryLimitReachedTxt) && { disabled: true })}
                      >
                        {preWhatsappButtonText}
                      </div>
                    </div>
                  </div>
                )}
                {showSkipBtn && (
                  <div>
                    <div style={{ padding: 10 }}>
                      <div
                        // className='codk-otpw-send'
                        onClick={onSkipButtonClick}
                      >
                        <div
                          // className='codk-otpw-skip-btn-div'
                          style={{
                            backgroundColor: preSecondaryButtonColor,
                            margin: "0px",
                            borderRadius: "5px",
                            textAlign: "center",
                            width: "100%",
                            padding: "10px",
                            marginBottom: "0px",
                            lineHeight: "20pt",
                            color: preSecondaryButtonFontColor,
                            display: "block",
                            outline: "none",
                            cursor: "pointer",
                            fontSize: "10pt",
                          }}
                        >
                          {skipBtnText}
                        </div>
                      </div>
                    </div>
                  </div>
                )}

                {showCodKSendLoader && (
                  <>
                    <div className="codk-otpw-loader-container">
                      <div className="codk-otpw-loader-l"></div>
                      <div className="codk-otpw-loader"></div>
                      <div className="codk-otpw-loader-r"></div>
                    </div>
                  </>
                )}

                {/* codk-otpw-phone-msg-container start */}

                {/* codk-otpw-phone-msg-container end */}
              </div>
            )}

            {showCodKVerify && !showCodKPhone && (
              <div className={CODK_OTP_VERIFY_CARD_WRAPPER_CLASS}>
                <div className={CODK_OTP_VERIFY_CARD_CLASS}>
                  <div className={CODK_OTP_WRAPPER_CLASS}>
                    <input
                      aria-invalid={true}
                      ref={inputRef}
                      placeholder={I18n.t("cart_otp_widget.enter_code")}
                      autoCapitalize="off"
                      spellCheck="false"
                      auto-complete="one-time-code"
                      className="codk-otpw-phone-input"
                      style={{ appearance: "none" }}
                      name="otpBox"
                      onChange={onOtpChange}
                      id="birdchime-otp-verify"
                      value={otp}
                      maxLength={4}
                      inputMode="numeric"
                      autoComplete="one-time-code"
                    />
                  </div>

                  <div
                    className={CODK_OTP_VERIFY_BTN_WRAPPER_CLASS}
                    onClick={onVerifyBtnClick}
                    ref={verifyBtnRef}
                    {...((showCodKVerified || showMaxRetryLimitReachedTxt) && {
                      disabled: true,
                    })}
                  >
                    <div
                      //className={CODK_OTP_VERIFY_BTN_CLASS}
                      style={{
                        backgroundColor: prePrimaryButtonColor,
                        margin: "0px",
                        borderRadius: "5px",
                        height: "100%",
                        padding: "2px",
                        textAlign: "center",
                        width: "100%",
                        marginBottom: "0px",
                        color: prePrimaryButtonFontColor,
                        outline: "none",
                        cursor: "pointer",
                        fontSize: "13pt",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                      }}
                      {...((showCodKVerified ||
                        showMaxRetryLimitReachedTxt) && { disabled: true })}
                    >
                      {verifyBtnText}
                    </div>
                  </div>
                </div>

                {showCodKVerifyLoader && (
                  <>
                    <div className="codk-otpw-loader-container">
                      <div className="codk-otpw-loader-l"></div>
                      <div className="codk-otpw-loader"></div>
                      <div className="codk-otpw-loader-r"></div>
                    </div>
                  </>
                )}

                {/* codk-otpw-verify-msg-container  style start */}
                <div className="codk-otpw-verify-msg-container">
                  <div className="codk-otpw-wrong-otp-msg-wrapper">
                    <div className="codk-otpw-wrong-otp-msg">
                      {showWrongOtpText && wrongOtpText}
                      {showServerErrorText && SERVER_ERROR_TEXT}
                    </div>
                    <div className="codk-otpw-wrong-otp-msg-right"></div>
                  </div>

                  <div className="codk-otpw-otp-sent-wrapper">
                    <div className="codk-otpw-otp-sent-msg">
                      {showOtpSentText &&
                        `${OTP_SENT_TEXT} ${countryCallingCode} ${phoneNumber}`}
                      {!showOtpSentText && <span>&nbsp;</span>}
                    </div>
                    <div className="codk-otpw-otp-sent-right">
                      <span
                        className="cod-otp-w-change-link"
                        onClick={onChangePhonNoBtnClick}
                      >
                        {CHANGE_LINK_TEXT}
                      </span>
                    </div>
                  </div>

                  <div className="codk-otpw-wrong-otp-resend-wrapper">
                    <div className="codk-otpw-otp-resend-msg">
                      {showDidNotReceiveOtpText && DID_NOT_RECEIVE_OTP_TEXT}
                    </div>
                    <div className="codk-otpw-otp-resend-right">
                      {showResendTimer && (
                        <span className="codk-resend-counter">
                          {I18n.t("cart_otp_widget.resend_code_timer", {
                            timer: timer,
                          })}
                        </span>
                      )}
                      {showResendLink && (
                        <span
                          className="codk-resend-link"
                          onClick={onResendOtpBtnClick}
                        >
                          {RESEND_LINK_TEXT}
                        </span>
                      )}
                    </div>
                  </div>
                </div>
                {/* codk-otpw-verify-msg-container  style end */}
              </div>
            )}
          </div>
        )}
      </form>
    </>
  );
};
const CartOTPWidget = ({ enableCheckOutFn, disableCheckoutFn }) => {
  if (
    window?.location?.pathname?.includes("/products") ||
    window?.location?.pathname?.includes("/cart")
  ) {
    return (
      <>
        <CodkOTPWidget
          enableCheckOutFn={enableCheckOutFn}
          disableCheckoutFn={disableCheckoutFn}
        />
      </>
    );
  }
};

export default CartOTPWidget;
