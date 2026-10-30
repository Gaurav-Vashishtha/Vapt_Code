import React, { useState, useEffect, useRef } from "react";
import { camelizeKeys } from "humps";
import useAxios from "axios-hooks";
import I18n, { availableLocales } from "../i18n-lang-script";
import useInterval from "@use-it/interval";
import ResendOtp from "./ResendOtp";
import "./application.css";
import { renderToString } from "react-dom/server";
import { render } from "react-dom";
import { debugLog } from "../Modal/utilities/otpUtils";

// import currencyCodes from './currency_codes.json'
// const currencyCodes = require('./currency_codes.json')

let documentLocale =
  Shopify?.locale ||
  document?.documentElement?.getAttribute("lang")?.substring(0, 2);
if (Shopify?.shop == "costumebaie.myshopify.com") {
  documentLocale = "ro";
}

I18n.locale = Object.keys(I18n.translations).includes(documentLocale)
  ? documentLocale
  : I18n.defaultLocal;

const useScriptSettings = (defaultSetting = {}) => {
  const [settings, setSettings] = useState(defaultSetting);
  useEffect(() => {
    fetch(
      `https://${process.env.APP_HOST}/script/settings?domain=${window.Shopify.shop}`
    )
      .then((res) => res.json())
      .then((data) => {
        setSettings(camelizeKeys(data));
      });
  }, [setSettings]);
  return [settings];
};

const useOrderConfirmation = (customer_number) => {
  const [confirmation, setConfirmation] = useState({ customer_number });
  const [{ data, loading, error }, refetch] = useAxios({
    url: `https://${process.env.APP_HOST}/order_confirmations/default`,
    method: "GET",
    headers: {
      "Cache-Control": "no-cache, no-store, must-revalidate",
      Pragma: "no-cache",
      Expires: 0,
    },
    params: {
      order_id: window?.Shopify?.checkout?.order_id,
      order_url: window.location.pathname,
      full_url: window.location.href,
      domain: window.Shopify.shop,
    },
  });
  useEffect(() => {
    setConfirmation(data);
  }, [data]);

  const resetNumber = () =>
    setConfirmation({
      ...confirmation,
      customer_number: null,
    });
  return [{ data: confirmation, loading, error }, refetch, resetNumber];
};

const useRenderOtpBoxStatus = () => {
  const [otpBoxStatus, setOtpBoxStatus] = useState(null);
  const [{ data, loading, error }, refetchOTPStatus] = useAxios({
    url: `https://${process.env.APP_HOST}/order_confirmations/render_otp_box/`,
    method: "GET",
    headers: {
      "Cache-Control": "no-cache, no-store, must-revalidate",
      Pragma: "no-cache",
      Expires: 0,
    },
    params: {
      checkout_token: window?.Shopify?.Checkout?.token,
      domain: window?.Shopify?.shop,
      order_id: window?.Shopify?.checkout?.order_id,
    },
  });

  debugLog("data from useRenderOtpBoxStatus", data);
  useEffect(() => {
    if (data) {
      setOtpBoxStatus(data);
    }
  }, [data]);

  const resetOtpBoxStatus = () => {
    setOtpBoxStatus({
      ...otpBoxStatus,
      phone: null,
    });
    setOtpBoxStatus(null);
  };

  return [
    { otpBoxStatus: otpBoxStatus, loading, error },
    refetchOTPStatus,
    resetOtpBoxStatus,
  ];
};

const ShopifyLoaderIcon = () => (
  <svg
    className="icon-svg icon-svg--color-accent icon-svg--size-64 icon-svg--spinner full-page-overlay__icon"
    aria-hidden="true"
    focusable="false"
  >
    <use xlinkHref="#spinner-large">
      <svg id="spinner-large">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="-270 364 66 66">
          <path d="M-237 428c-17.1 0-31-13.9-31-31s13.9-31 31-31v-2c-18.2 0-33 14.8-33 33s14.8 33 33 33 33-14.8 33-33h-2c0 17.1-13.9 31-31 31z"></path>
        </svg>
      </svg>
    </use>
  </svg>
);

const ShopifyLoaderFull = () => {
  return (
    <div className="full-page-overlay">
      <div className="full-page-overlay__wrap">
        <div
          data-processing-order=""
          className="full-page-overlay__content"
          role="region"
          aria-describedby="full-page-overlay__processing-text"
          tabIndex="-1"
        >
          <ShopifyLoaderIcon />
          <div id="full-page-overlay__processing-text">
            <h3 className="full-page-overlay__title">
              {I18n.t("script.order_being_processed")}
            </h3>
            <p className="full-page-overlay__text">
              {I18n.t("script.if_not_redirected")}
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

const PhoneField = ({ orderId, onNumberChanged }) => {
  const [phone, setPhone] = useState("");
  const [error, setError] = useState(false);

  const inputRef = useRef(null);

  const [{ data, loading, error: updateError }, updatePhone] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/order_confirmations/update_ph_and_send_otp`,
      method: "POST",
    },
    { manual: true }
  );

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const onPhoneChange = (e) => {
    setPhone(e.target.value.replace(/[^0-9|+|\s]/g, ""));
  };

  const onSubmit = () => {
    updatePhone({
      data: {
        order_id: orderId,
        customer_number: phone,
      },
    }).then((resp) => {
      if (resp.status === 200) {
        onNumberChanged(phone);
      }
    });
  };

  return (
    <div>
      <div className="fieldset">
        <div className="field--two-thirds field field--required field--show-floating-label">
          <div className={`${(error || updateError) && "field--error"}`}>
            <div className={`field__input-btn-wrapper`}>
              <div className="field__input-wrapper field__input-wrapper--flag-right">
                <label
                  className="field__label field__label--visible"
                  htmlFor="birdchime-customer-phone"
                >
                  {I18n.t("script.mobile_phone_number")}
                </label>
                <input
                  aria-invalid={true}
                  ref={inputRef}
                  placeholder={I18n.t("script.mobile_phone_number")}
                  autoCapitalize="off"
                  spellCheck="false"
                  autoComplete="mobile tel"
                  className="field__input"
                  type="tel"
                  name=""
                  id="birdchime-customer-phone"
                  value={phone}
                  maxLength={16}
                  onChange={onPhoneChange}
                  inputMode="numeric"
                />
              </div>
              <button
                type="submit"
                onClick={onSubmit}
                className={`field__input-btn btn ${loading && "btn--loading"}`}
              >
                <span className="btn__content visually-hidden-on-mobile">
                  {I18n.t("script.submit")}
                </span>
                <svg
                  className="icon-svg icon-svg--size-16 btn__icon shown-on-mobile"
                  aria-hidden="true"
                  focusable="false"
                >
                  {" "}
                  <use xlinkHref="#arrow">
                    <svg id="arrow">
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 16 16"
                      >
                        <path d="M16 8.1l-8.1 8.1-1.1-1.1L13 8.9H0V7.3h13L6.8 1.1 7.9 0 16 8.1z"></path>
                      </svg>
                    </svg>
                  </use>{" "}
                </svg>
                <svg
                  className="icon-svg icon-svg--size-18 btn__spinner icon-svg--spinner-button"
                  aria-hidden="false"
                  focusable="false"
                >
                  {" "}
                  <use xlinkHref="#spinner-button">
                    <svg id="spinner-button">
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 20 20"
                      >
                        <path d="M20 10c0 5.523-4.477 10-10 10S0 15.523 0 10 4.477 0 10 0v2c-4.418 0-8 3.582-8 8s3.582 8 8 8 8-3.582 8-8h2z"></path>
                      </svg>
                    </svg>
                  </use>{" "}
                </svg>
              </button>
            </div>
            {(error || updateError) && (
              <p className="field__message field__message--error">
                {I18n.t("script.enter_valid_phone")}
              </p>
            )}
          </div>
        </div>
      </div>
      {/* <div align="left" >

    </div> */}
    </div>
  );
};

const VerifyField = ({
  orderId,
  phone,
  onVerify,
  onNumberChange,
  settings,
  otpBoxStatus,
}) => {
  const { template, otpFallbackText } = settings;
  const [otp, setOtp] = useState("");
  const [error, setError] = useState(false);
  const inputRef = useRef(null);
  const isOtpEnabled = template.includes("{{otp}}");
  const [{ data, loading, error: confirmError }, confirmOtp] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/order_confirmations/confirm`,
      method: "POST",
    },
    { manual: true }
  );

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const onOtpChange = (e) => {
    if (Number.isInteger(Number(e.target.value))) {
      setOtp(e.target.value);
    }
  };

  const [{ wdata, wloading, werror: wupdateError }, sendCodeOnWhatsapp] =
    useAxios(
      {
        url: `https://${process.env.APP_HOST}/order_confirmations/send_code_on_whatsapp`,
        method: "POST",
      },
      { manual: true }
    );

  // const [{ wdata1, wloading1, werror: wupdateError1 }, skipButton] = useAxios({
  //   url: `https://${process.env.APP_HOST}/order_confirmations/skip_button`,
  //   method: 'POST'
  // }, { manual: true })

  const onWhatsappRequest = () => {
    sendCodeOnWhatsapp({
      data: {
        order_id: orderId,
      },
    }).then((resp) => {
      if (resp.status === 200) {
        document.getElementById("whatsapp_link").style.visibility = "hidden";
      }
    });
  };

  // const skipVerificationEvent = () => {
  //   skipButton({
  //     data: {
  //       order_id: orderId
  //     }
  //   }).then(resp => {
  //     if (resp.status === 200) {
  //       location.reload();
  //       // document.getElementById("whatsapp_link").style.visibility='hidden'
  //     }
  //   })
  // }

  const onSubmit = () => {
    confirmOtp({
      data: {
        order_id: orderId,
        otp: otp,
      },
    })
      .then((resp) => {
        if (resp.status === 200) {
          onVerify();
          if (resp?.data.status === "COD-Verified" && settings.customScript) {
            eval(settings.customScript);
          }
        }
      })
      .catch((e) => {});
  };

  const WhatsappLink = `${process.env.WHATSAPP_COUNTRIES}`
    .split(",")
    .includes(window.Shopify.country) === true &&
    settings.whatsappEnabled === true && (
      <a
        className="link--small"
        id="whatsapp_link"
        onClick={onWhatsappRequest}
        style={{ cursor: "pointer" }}
      >
        {I18n.t("script.send_code_on_whatsapp")}
      </a>
    );

  // const skipVerification = (
  //   <>
  //   <br/>
  //   <a className="link--small" id="whatsapp_link" onClick={skipVerificationEvent} style={{cursor: 'pointer'}}>
  //     Skip Verification
  //   </a>
  //   </>
  // )

  return (
    <>
      <div
        className={
          settings.id == 83
            ? "notice notice--warning1 default-background"
            : "notice notice--warning default-background"
        }
        data-banner="true"
        role="status"
        tabIndex="-1"
        aria-atomic="true"
        aria-live="polite"
        style={{ display: "flex", alignItems: "center" }}
      >
        <svg
          className="icon-svg icon-svg--size-24 notice__icon"
          aria-hidden="true"
          focusable="false"
        >
          <use xlinkHref="#warning">
            <svg id="warning">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 22">
                <path d="M15.286 2.386l7.91 13.857C25.01 19.423 23.65 22 20.16 22H3.84C.35 22-1.01 19.427.805 16.243l7.91-13.857c1.815-3.178 4.754-3.185 6.57 0zm-1.737.992c-1.05-1.838-2.05-1.837-3.1 0L2.54 17.235C1.468 19.122 1.93 20 3.84 20h16.32c1.91 0 2.374-.88 1.298-2.765l-7.91-13.857zM12 6.5c.552 0 1 .448 1 1V12c0 .552-.448 1-1 1s-1-.448-1-1V7.5c0-.552.448-1 1-1zm-1.5 10c0-.828.666-1.5 1.5-1.5.828 0 1.5.666 1.5 1.5 0 .828-.666 1.5-1.5 1.5-.828 0-1.5-.666-1.5-1.5z"></path>
              </svg>
            </svg>
          </use>
        </svg>
        <div
          className="notice__content"
          style={{
            display: "flex",
            flexDirection: "row",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          {isOtpEnabled && (
            <>
              {otpBoxStatus?.render_otp_box === true && !orderId ? (
                <p className="notice__text">{`Sending OTP to registered number ...`}</p>
              ) : (
                // <p
                //   className="notice__text"
                //   dangerouslySetInnerHTML={{
                //     __html: I18n.t("script.enter_otp_msg", {
                //       number: phone,
                //     }),
                //   }}
                // />
                <p
                  className="notice__text"
                  dangerouslySetInnerHTML={{
                    __html: I18n.t("script.enter_otp_msg", {
                      number: phone,
                    }),
                  }}
                />
              )}
            </>
          )}
          {!isOtpEnabled && (
            <p
              className="notice__text"
              dangerouslySetInnerHTML={{
                __html: I18n.t("script.click_verify_link", {
                  number: phone,
                }),
              }}
            />
          )}
          {(settings.maxRetries == undefined || settings.maxRetries > 1) && (
            <a
              style={{
                display: "inline-block",
                textAlign: "right",
                minWidth: 66,
                color: settings.id == 2427 ? "black" : "",
              }}
              className="link--small"
              href="#"
              onClick={onNumberChange}
            >
              <span aria-hidden="true">{I18n.t("script.change")}</span>
            </a>
          )}
        </div>
      </div>
      {isOtpEnabled && (
        <>
          {otpFallbackText && (
            <p
              style={{ marginBottom: 18 }}
              dangerouslySetInnerHTML={{ __html: otpFallbackText }}
            />
          )}
          <div className="fieldset">
            <div className="field--two-thirds field field--required field--show-floating-label">
              <div className={`${(error || confirmError) && "field--error"}`}>
                <div className={`field__input-btn-wrapper`}>
                  <div className="field__input-wrapper field__input-wrapper--flag-right">
                    <label
                      className="field__label field__label--visible"
                      htmlFor="birdchime-otp-verify"
                    >
                      {I18n.t("script.enter_otp")}
                    </label>
                    <input
                      aria-invalid={true}
                      ref={inputRef}
                      placeholder="Mobile phone number"
                      autoCapitalize="off"
                      spellCheck="false"
                      className="field__input"
                      style={{
                        appearance: "none",
                        border:
                          settings.id == 2427
                            ? "1px solid black"
                            : "1px solid black",
                      }}
                      name=""
                      id="birdchime-otp-verify"
                      value={otp}
                      onChange={onOtpChange}
                      maxLength={6}
                      inputMode="numeric"
                      autoComplete="one-time-code"
                    />
                  </div>
                  <button
                    type="submit"
                    style={{
                      border: settings.id == 2427 ? "1px solid black" : "none",
                    }}
                    onClick={onSubmit}
                    className={`field__input-btn btn ${
                      loading && "btn--loading"
                    }`}
                  >
                    <span className="btn__content visually-hidden-on-mobile">
                      {I18n.t("script.submit")}
                    </span>
                    <svg
                      className="icon-svg icon-svg--size-16 btn__icon shown-on-mobile"
                      aria-hidden="true"
                      focusable="false"
                    >
                      {" "}
                      <use xlinkHref="#arrow">
                        <svg id="arrow">
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            viewBox="0 0 16 16"
                          >
                            <path d="M16 8.1l-8.1 8.1-1.1-1.1L13 8.9H0V7.3h13L6.8 1.1 7.9 0 16 8.1z"></path>
                          </svg>
                        </svg>
                      </use>{" "}
                    </svg>
                    <svg
                      className="icon-svg icon-svg--size-18 btn__spinner icon-svg--spinner-button"
                      aria-hidden="false"
                      focusable="false"
                    >
                      {" "}
                      <use xlinkHref="#spinner-button">
                        <svg id="spinner-button">
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            viewBox="0 0 20 20"
                          >
                            <path d="M20 10c0 5.523-4.477 10-10 10S0 15.523 0 10 4.477 0 10 0v2c-4.418 0-8 3.582-8 8s3.582 8 8 8 8-3.582 8-8h2z"></path>
                          </svg>
                        </svg>
                      </use>{" "}
                    </svg>
                  </button>
                </div>
                {(error || confirmError) && (
                  <p className="field__message field__message--error">
                    {I18n.t("script.invalid_otp")}
                  </p>
                )}
              </div>
              {(settings.maxRetries == undefined ||
                settings.maxRetries > 1) && (
                <div style={{ display: "block", marginTop: "10px" }}>
                  <ResendOtp
                    orderId={orderId}
                    phone={phone}
                    settings={settings}
                  />
                </div>
              )}
              {WhatsappLink}
              {/* {
             skipVerification
          } */}
            </div>
          </div>
        </>
      )}
    </>
  );
};

const ContentBox = ({ title, children }) => {
  return (
    <div style={{ marginBottom: "1em" }}>
      <div className="content-box">
        {title && (
          <div className="content-box__row">
            <h2>{title}</h2>
          </div>
        )}
        <div className="content-box__row">{children}</div>
      </div>
    </div>
  );
};

let COD_FEES_ADDED = false;

const addCODFees = (settings, data) => {
  if (COD_FEES_ADDED) return;
  COD_FEES_ADDED = true;
  let estimatedPrice = data?.order_amount;
  let currency =
    window?.Shopify?.checkout?.currency || window?.Shopify?.currency?.active;
  // currency = currencyCodes[currency] == undefined ? currency : currencyCodes[currency]
  let total = parseFloat(estimatedPrice) + parseFloat(data?.cod_fee);

  window.Shopify.Checkout.OrderStatus.addContentBox(
    "<h2>Cash on delivery instructions</h2>",
    "<p>" + settings.codInstrutction + "</p>"
  );

  document
    .querySelector(".order-summary .total-line-table__tbody")
    .insertAdjacentHTML(
      "beforeend",
      '<tr class="total-line"> <th class="total-line__name" id="cod_fees" scope="row"> <span> ' +
        settings.codLabel +
        ' </span> </th> <td class="total-line__price"> <span class="skeleton-while-loading order-summary__emphasis" data-checkout-total-shipping-target="0"> ' +
        new Intl.NumberFormat(I18n.locale || "en", {
          style: "currency",
          currency: currency,
        }).format(data?.cod_fee) +
        " </span> </td></tr>"
    ),
    document
      .querySelectorAll(
        ".total-line-table__footer .total-line [data-checkout-payment-due-target], .order-summary__emphasis[data-checkout-payment-due-target]"
      )
      .forEach(function (e) {
        e.innerHTML = new Intl.NumberFormat(I18n.locale || "en", {
          style: "currency",
          currency: currency,
        }).format(total);
      });
  if (
    document.getElementsByClassName(
      "payment-due__currency remove-while-loading"
    ) != undefined &&
    document.getElementsByClassName(
      "payment-due__currency remove-while-loading"
    )[0] != undefined
  ) {
    // document.getElementsByClassName('payment-due__currency remove-while-loading')[0].innerHTML=currency;
  }
};

let PREPAID_LINK_ADDED = false;
const addPrepaidLink = (settings, order) => {
  if (PREPAID_LINK_ADDED || settings.prepaidEnabled != true) return;
  PREPAID_LINK_ADDED = true;

  var countDownDate =
    new Date(order?.created_at).getTime() + settings.prepaidExpiry * 60000;

  // Update the count down every 1 second
  var x = setInterval(function () {
    // Get today's date and time
    var now = new Date().getTime();

    // Find the distance between now and the count down date
    var distance = countDownDate - now;

    // Time calculations for days, hours, minutes and seconds
    var days = Math.floor(distance / (1000 * 60 * 60 * 24));
    var hours = Math.floor(
      (distance % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60)
    );
    var minutes = Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60));
    var seconds = Math.floor((distance % (1000 * 60)) / 1000);

    // Display the result in the element with id="demo"
    document.getElementById("timer").innerHTML =
      days + "d " + hours + "h " + minutes + "m " + seconds + "s ";

    // If the count down is finished, write some text
    if (distance < 0) {
      clearInterval(x);
      document.getElementById("timer").innerHTML = "EXPIRED";
      document.getElementById("codfirm_payment_btn").disabled = true;
      document.getElementById("codfirm_payment_btn").style.backgroundColor =
        "Grey";
    }
  }, 1000);

  function getPaymentLink() {
    document.getElementById("codfirm_payment_btn").disabled = true;
    document.getElementById("codfirm_payment_btn").style.backgroundColor =
      "Grey";
    fetch(
      `https://${process.env.APP_HOST}/order_confirmations/create_prepaid_link/?domain=${window.Shopify.shop}&order_id=${order.order_id}`
    )
      .then((response) => response.json())
      //handle response
      .then((data) => {
        //handle data
        window.location.href = data.response;
        document.getElementById("codfirm_payment_btn").disabled = false;
        document.getElementById("codfirm_payment_btn").style.backgroundColor =
          "";
      })
      .catch((error) => {
        document.getElementById("codfirm_payment_btn").disabled = false;
        document.getElementById("codfirm_payment_btn").style.backgroundColor =
          "";
      });
  }
  var heading = settings.prepaidHeading;
  var subHeading = settings.prepaidSubHeading;
  var prepaidBannerColor = settings.prepaidBannerColor;
  var content_html =
    '<div class="content-box__row content-box__row--no-padding">' +
    '<div class="content-box" id="no-border banner" style="background :' +
    prepaidBannerColor +
    '; margin-bottom : 0;">' +
    '<div id="payment_div"> <div class="content-box__row content-box__row--no-border">' +
    '<h1 style="font-weight : 700;font-size: 2rem; text-align: center;">' +
    heading +
    "</h1>" +
    '<div class="payment_info_div" ">' +
    subHeading +
    "</div>" +
    "</div>" +
    '<div class="content-box__row"> ' +
    "<div class=payment_info_div>" +
    '<button type="submit" onclick="getPaymentLink()" class="payment_btn" id="codfirm_payment_btn">' +
    '<span class="btn__content">Pay Online</span>' +
    "</button>" +
    "</div>" +
    "<div class=payment_info_div>" +
    '<h2 style="font-weight: 500">Offer ends in</h2>' +
    '<div id="timer"></div>' +
    "</div>" +
    "</div>" +
    "</div>" +
    "</div>" +
    "</div>";

  window.getPaymentLink = getPaymentLink;
  window.prepaid_box_content = content_html;
  document.getElementById("birdchime-cod-box").innerHTML = content_html;
};

let thankyouMessageAdded = false;

const App = ({ settings }) => {
  const [{ data, loading, error }, refetchPhone, reset] = useOrderConfirmation(
    window?.Shopify?.checkout?.shipping_address?.phone ||
      window?.Shopify?.checkout?.billing_address?.phone
  );
  const [{ otpBoxStatus }, refetchOtpStatus, resetOtpBoxStatus] =
    useRenderOtpBoxStatus();

  const [isChanging, setIsChanging] = useState(false);

  // window?.Shopify.checkout.shipping_address.phone ||
  // window?.Shopify.checkout.billing_address.phone ||
  // data?.customer_number

  const phone = data?.customer_number;

  const [verified, setVerified] = useState(false);

  function setWithExpiry(key, value, ttl) {
    const now = new Date();

    // `item` is an object which contains the original value
    // as well as the time when it's supposed to expire
    const item = {
      value: value,
      expiry: now.getTime() + ttl,
    };
    debugLog(now.getTime());
    debugLog(now.getTime() + ttl);
    localStorage.setItem(key, JSON.stringify(item));
  }

  function getWithExpiry(key) {
    const itemStr = localStorage.getItem(key);
    // if the item doesn't exist, return null
    if (!itemStr) {
      return null;
    }
    const item = JSON.parse(itemStr);
    const now = new Date();
    // compare the expiry time of the item with the current time
    if (now.getTime() > item.expiry) {
      // If the item is expired, delete the item from storage
      // and return null
      localStorage.removeItem(key);
      return null;
    }
    return item.value;
  }

  const onVerify = () => {
    setVerified(true);
    document
      .querySelector(".main__content")
      .querySelector(".step").hidden = false;
    if (
      window.Shopify.shop === "sofapotato.myshopify.com" &&
      getWithExpiry("isReloaded") != "1"
    ) {
      //)
      setWithExpiry("isReloaded", "1", 30000);
      window.location.reload(false);
    }
  };

  const onNumberChange = () => {
    reset();
  };

  const [retryCount, setRetryCount] = useState(5);

  useEffect(() => {
    if (data?.id || otpBoxStatus?.render_otp_box === true) {
      document.body.style.opacity = 1;
    }
  }, [data?.id, otpBoxStatus]);

  useEffect(() => {
    if (retryCount < 4) {
      document.body.style.opacity = 1;
    }
  }, [retryCount]);

  useInterval(
    () => {
      if (!data?.id && !loading) {
        setRetryCount((r) => r - 1);
        refetchPhone();
      }
    },
    !data?.id && retryCount > 0 ? 2100 : null
  );

  useEffect(() => {
    if (data?.status === "COD-Verified") {
      onVerify();
    } else if (
      (data?.status === "Pending" || otpBoxStatus?.render_otp_box === true) &&
      settings.sms === true
    ) {
      document
        .querySelector(".main__content")
        .querySelector(".step").hidden = true;
    }
  }, [data?.status, otpBoxStatus]);

  if (data?.id) {
    const storageLocale = window?.localStorage?.getItem("cod-king:locale");
    if (availableLocales.includes(storageLocale)) {
      I18n.locale = storageLocale;
    }
  }

  if (data?.customer_locale && I18n.locale !== data?.customer_locale) {
    if (availableLocales.includes(data?.customer_locale?.substring(0, 2))) {
      I18n.locale = data?.customer_locale?.substring(0, 2);
    }
  }

  if (settings.id == 1895) {
    I18n.locale = "ro";
  }

  if (
    settings.prepaidEnabled == true &&
    data?.order_id &&
    data?.status != "Non-COD" &&
    data?.is_cod_order == true
  ) {
    addPrepaidLink(settings, data);
  }
  if (
    settings.codFeeEnabled &&
    data?.order_id &&
    data?.status != "Non-COD" &&
    data?.is_cod_order == true
  ) {
    addCODFees(settings, data);
  }
  if (
    settings.thankyouMessage != null &&
    settings.thankyouMessage != "" &&
    !thankyouMessageAdded
  ) {
    window.Shopify.Checkout.OrderStatus.addContentBox(settings.thankyouMessage);
    thankyouMessageAdded = true;
  }

  if (settings.sms && !verified && data?.status === "Pending") {
    return (
      <>
        <ContentBox
          title={
            <span
              dangerouslySetInnerHTML={{
                __html: I18n.t("script.confirm_order"),
              }}
            />
          }
        >
          {false && (
            <p style={{ marginBottom: 15 }}>
              {I18n.t("script.verify_for_smooth_delivery")}
            </p>
          )}
          <div className="floating-labels">
            {phone ? (
              <VerifyField
                orderId={data.order_id}
                phone={phone}
                onVerify={onVerify}
                onNumberChange={onNumberChange}
                settings={settings}
                otpBoxStatus={otpBoxStatus}
              />
            ) : (
              <PhoneField
                orderId={data.order_id}
                onNumberChanged={() => refetchPhone()}
              />
            )}
          </div>
        </ContentBox>
        {settings.prepaidEnabled == true &&
          data?.order_id &&
          data?.is_cod_order == true &&
          data?.status != "Non-COD"}{" "}
        {addPrepaidLink(settings, data)}
      </>
    );
  }
  return null;
};

const AppScript = () => {
  const [settings] = useScriptSettings();
  const isOtpEnabled = settings?.template?.includes("{{otp}}");
  const isLinkEnabled = settings?.template?.includes("{{link}}");

  useEffect(() => {
    if ("sms" in settings && !settings?.sms) {
      document.body.style.opacity = 1;
    }
    if ("sms" in settings && !isOtpEnabled && !isLinkEnabled) {
      document.body.style.opacity = 1;
    }
  }, [settings]);

  if (
    (settings.thankyouMessage != null && settings.thankyouMessage != "") ||
    settings.prepaidEnabled ||
    settings.codFeeEnabled ||
    (settings.sms && (isOtpEnabled || isLinkEnabled))
  ) {
    return <App settings={settings} />;
  }
  return null;
};

const AppScriptContainer = () => {
  useEffect(() => {
    if (
      (!window?.Shopify?.checkout?.order_id &&
        window?.location?.pathname?.includes("/thank_you")) ||
      (!window?.Shopify?.checkout?.order_id &&
        window?.Shopify?.shop == "sooqaman.myshopify.com" &&
        window?.location?.pathname?.includes("/orders"))
    ) {
      if (
        window?.Shopify?.shop == "sooqaman.myshopify.com" &&
        !window.location.hash
      ) {
        window.location = window.location + "#loaded";
        window.location?.reload();
      }
      if (window?.Shopify?.shop != "sooqaman.myshopify.com") {
        window.location?.reload();
      }
    }
  }, [window]);

  if (
    window?.Shopify?.checkout?.order_id ||
    !window?.location?.pathname?.includes("/thank_you")
  ) {
    return <AppScript />;
  }
  return null;
};

export default AppScriptContainer;
