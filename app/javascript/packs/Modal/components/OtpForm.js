import React, { useState, useEffect, useRef } from "react";
import CountryCode from "../../Components/CountryCode"; // Adjust this path if necessary
import OtpInput from "react-otp-input";

import { Edit } from "lucide-react";

import VerifiedLottiePlayer from "./assets/VerifiedLottiePlayer";
import PhoneInputBox from "./PhoneInputBox";
import { useAppContext } from "../context/AppContext";
import ShippingAddress from "./shippingflow/ShippingAddress";
import AddOrEditAddress from "./shippingflow/addOrEditAddress";
import useOtpStore from "../stores/otpStore";
import {
  ENTER_CODE_SEND_TO,
  PLEASE_ENTER_VALID_PHONE_NUMBER,
  VERIFY_MOBILE_NUMBER,
  VERIFYING_TEXT,
  CODK_MAX_RETRY_TEXT,
  OTP_VERIFIED_TEXT,
  SERVER_ERROR_TEXT,
  DID_NOT_RECEIVE_OTP_TEXT,
  RESEND_LINK_TEXT,
  getSessionValue,
  debugLog,
} from "../utilities/otpUtils";
import OtpVerifiedMessage from "./OTPVerifiedMessage";
import { shopifyAddToCartForBuyNow } from "../services/cartService";
import { IS_BUY_NOW_BUTTON } from "../services/domUtils";
const OtpForm = ({ onClose }) => {
  // const { phone } = useAppContext();
  const {
    otpData,
    setOtp,
    setStep,
    handlePhoneSubmit,
    handleOtpSubmit,
    handleResendOtp,
    onChangePhonNoBtnClick,
    onSkipButtonClick,
    setError,
    isCartReady,
    initializeFetchProductDetails,
  } = useOtpStore();

  const {
    step,
    otp,
    phoneNumber,
    timer,
    isLoading,
    error,
    showResendLink,
    showServerErrorText,
    session,
    showMaxRetryLimitReachedTxt,
  } = otpData;

  const settings = getSessionValue("settingSession");
  const {
    heading,
    subHeading,
    redirectText,
    prePrimaryButtonColor,
    prePrimaryButtonFontColor,
    sendBtnText,
    preWhatsappButton,
    preWhatsappButtonText,
    showSkipBtn,
    preSecondaryButtonColor,
    preSecondaryButtonFontColor,
    skipBtnText,
    verifyBtnText,
  } = settings;

  const [isSmsLoading, setIsSmsLoading] = useState(false);
  const [isWhatsappLoading, setIsWhatsappLoading] = useState(false);
  const [isSkipLoading, setIsSkipLoading] = useState(false);
  const isOtpVerified = !!(session && session.isOTPVerified);

  const frameRef = useRef(null);
  useEffect(() => {
    debugLog("Current step:", step);
  }, [step]);

  useEffect(() => {
    let isMounted = true;

    const initialize = async () => {
      try {
        if (!isMounted) return;

        if (IS_BUY_NOW_BUTTON && isMounted) {
          await shopifyAddToCartForBuyNow();
        }
        if (isMounted) {
          await initializeFetchProductDetails();
        }
      } catch (error) {
        console.error("Error initializing DesktopOrderSummary:", error);
      }
    };

    initialize();

    return () => {
      isMounted = false;
    };
  }, []);

  useEffect(() => {
    const style = document.createElement("style");
    style.innerHTML = `
      input[type="number"]::-webkit-inner-spin-button,
      input[type="number"]::-webkit-outer-spin-button {
        -webkit-appearance: none;
        margin: 0;
      }
      input[type="number"] {
        -moz-appearance: textfield;
        appearance: none;
      }
    `;
    document.head.appendChild(style);
    return () => document.head.removeChild(style);
  }, []);

  const handlePhoneSubmitSms = async () => {
    setIsSmsLoading(true);
    try {
      await handlePhoneSubmit("SMS");
    } catch (error) {
      console.error("Error submitting SMS:", error);
    } finally {
      setIsSmsLoading(false);
    }
  };

  const handlePhoneSubmitWhatsapp = async () => {
    setIsWhatsappLoading(true);
    try {
      await handlePhoneSubmit("WHATSAPP");
    } catch (error) {
      console.error("Error submitting WhatsApp:", error);
    } finally {
      setIsWhatsappLoading(false);
    }
  };

  const handleSkip = async () => {
    setIsSkipLoading(true);
    try {
      await onSkipButtonClick();
    } catch (error) {
      console.error("Error skipping:", error);
    } finally {
      setIsSkipLoading(false);
    }
  };

  // const iframeRef = useRef(null); // Reference for iframe

  // // Dynamically adjust iframe height
  // useEffect(() => {
  //   const updateIframeHeight = () => {
  //     if (iframeRef.current) {
  //       const iframe = iframeRef.current.node; // Access iframe DOM node
  //       if (iframe && iframe.contentWindow && iframe.contentWindow.document) {
  //         iframe.style.height = `${iframe.contentWindow.document.body.scrollHeight}px`;
  //       }
  //     }
  //   };

  //   // Check iframe content height periodically
  //   const intervalId = setInterval(updateIframeHeight, 100); // Adjust every 100ms

  //   // Cleanup on unmount
  //   return () => clearInterval(intervalId);
  // }, []);

  // useEffect(() => {
  //   let isMounted = true;

  //   const injectStyles = () => {
  //     const iframe = iframeRef.current?.node; // Access the iframe
  //     const iframeDoc = iframe?.contentWindow?.document;

  //     if (iframeDoc && isMounted) {
  //       // Create and inject the CSS styles into iframe's <head>
  //       const style = iframeDoc.createElement("style");
  //       style.innerHTML = `
  //       input[type="number"]::-webkit-inner-spin-button,
  //       input[type="number"]::-webkit-outer-spin-button {
  //         -webkit-appearance: none;
  //         margin: 0;
  //       }
  //       input[type="number"] {
  //         -moz-appearance: textfield; /* Firefox */
  //         appearance: none; /* General for all browsers */
  //       }
  //     `;
  //       iframeDoc.head.appendChild(style);

  //       // Cleanup styles when the component or iframe unmounts
  //       return () => {
  //         if (iframeDoc.head.contains(style)) {
  //           iframeDoc.head.removeChild(style);
  //         }
  //       };
  //     }
  //   };

  //   const iframe = iframeRef.current?.node;

  //   if (iframe) {
  //     // Wait for iframe to load before injecting styles
  //     iframe.addEventListener("load", injectStyles);

  //     // Cleanup the listener on unmount
  //     return () => {
  //       iframe.removeEventListener("load", injectStyles);
  //       isMounted = false;
  //     };
  //   }
  // }, [iframeRef]);

  return (
    <>
      {step === 1 && (
        // <Frame
        //   ref={iframeRef}
        //   style={{
        //     width: "100%",
        //     border: "none", // No border for a clean look
        //     height: "100%",
        //     paddingT op: "25vh",
        //   }}
        //   head={[
        //     <link
        //       key="phone-input-styles"
        //       rel="stylesheet"
        //       href="https://unpkg.com/react-phone-input-2/lib/material.css"
        //     />,

        //     <style key="custom-styles">
        //       {`
        //     body {
        //       margin: 0;
        //       padding: 0;
        //       font-family: Arial, sans-serif;
        //     }
        //   `}
        //     </style>,
        //   ]}
        // >
        //   <div
        //     style={{
        //       background: "white",
        //       padding: "40px",
        //       borderRadius: "12px",
        //       boxShadow: "0 10px 40px rgba(0, 0, 0, 0.2)",
        //       maxWidth: "400px",
        //       // width: "100%",
        //       position: "relative",
        //       textAlign: "center",
        //       margin: "auto",
        //       zIndex: Number.MAX_SAFE_INTEGER,
        //     }}
        //   >
        //     <button
        //       onClick={onClose}
        //       style={{
        //         position: "absolute",
        //         top: "20px",
        //         right: "20px",
        //         background: "transparent",
        //         border: "none",
        //         fontSize: "26px",
        //         cursor: "pointer",
        //         color: "#495057",
        //         transition: "color 0.3s ease, transform 0.2s ease",
        //       }}
        //     >
        //       &times;
        //     </button>

        //     <div>
        //       <div
        //         style={{
        //           fontSize: "20px",
        //           fontWeight: "600",
        //           color: "#343a40",
        //           marginBottom: "20px",
        //         }}
        //       >
        //         {heading}
        //       </div>
        //       <div style={{ marginBottom: "30px" }}>
        //         {subHeading && (
        //           <p
        //             style={{
        //               fontSize: "14px",
        //               color: "#495057",
        //               marginBottom: "25px",
        //             }}
        //           >
        //             {subHeading}
        //           </p>
        //         )}
        //         {/* {isOtpVerified && redirectText && <p>{redirectText}</p>} */}
        //         {showMaxRetryLimitReachedTxt && <p>{CODK_MAX_RETRY_TEXT}</p>}

        //         <PhoneInputBox handlePhoneSubmitSms={handlePhoneSubmitSms} />
        //         {error && (
        //           <p
        //             style={{
        //               color: "red",
        //               marginBottom: "20px",
        //               fontSize: "14px",
        //             }}
        //           >
        //             {error}
        //           </p>
        //         )}
        //       </div>
        //       <div style={{ display: "flex", flexDirection: "column" }}>
        //         <button
        //           onClick={() => handlePhoneSubmitSms()}
        //           disabled={isLoading}
        //           style={{
        //             padding: "15px 0",
        //             backgroundColor: prePrimaryButtonColor || "#007bff",
        //             color: prePrimaryButtonFontColor || "white",
        //             boxShadow: "0 5px 15px rgba(82, 82, 84, 0.207)",
        //             fontSize: "16px",
        //             fontWeight: "600",
        //             letterSpacing: "0.5px",
        //             borderRadius: "8px",
        //             marginBottom: "15px",
        //             cursor: "pointer",
        //             transition:
        //               "background-color 0.3s ease, box-shadow 0.3s ease, transform 0.2s ease",
        //           }}
        //         >
        //           {isSmsLoading
        //             ? "Sending..."
        //             : sendBtnText + " →" || "Get OTP →"}
        //         </button>

        //         {preWhatsappButton && (
        //           <button
        //             onClick={() => {
        //               if (phoneNumber.length >= 9) {
        //                 handlePhoneSubmitWhatsapp();
        //               } else {
        //                 setError(PLEASE_ENTER_VALID_PHONE_NUMBER);
        //               }
        //             }}
        //             disabled={isLoading}
        //             style={{
        //               padding: "15px 0",
        //               backgroundColor: prePrimaryButtonColor || "#007bff",
        //               color: prePrimaryButtonFontColor || "white",
        //               boxShadow: "0 5px 15px rgba(82, 82, 84, 0.207)",
        //               fontSize: "16px",
        //               fontWeight: "600",
        //               letterSpacing: "0.5px",
        //               borderRadius: "8px",
        //               marginBottom: "15px",
        //               cursor: "pointer",
        //               transition:
        //                 "background-color 0.3s ease, box-shadow 0.3s ease, transform 0.2s ease",
        //             }}
        //           >
        //             {isWhatsappLoading
        //               ? "Sending..."
        //               : preWhatsappButtonText + " →" || "Get WhatsApp OTP →"}
        //           </button>
        //         )}

        //         {showSkipBtn && (
        //           <button
        //             onClick={handleSkip}
        //             disabled={isLoading}
        //             style={{
        //               padding: "15px 0",
        //               backgroundColor: preSecondaryButtonColor || "#f8f9fa",
        //               color: preSecondaryButtonFontColor || "#6c757d",
        //               fontSize: "16px",
        //               fontWeight: "600",
        //               letterSpacing: "0.5px",
        //               borderRadius: "8px",
        //               marginBottom: "15px",
        //               cursor: "pointer",
        //               transition:
        //                 "background-color 0.3s ease, box-shadow 0.3s ease, transform 0.2s ease",
        //             }}
        //           >
        //             {isSkipLoading
        //               ? "Skipping..."
        //               : skipBtnText + " →" || "Cancel →"}
        //           </button>
        //         )}
        //       </div>
        //     </div>
        //   </div>
        // </Frame>

        <div
          style={{
            background: "white",
            padding: "40px",
            borderRadius: "12px",
            boxShadow: "0 10px 40px rgba(0, 0, 0, 0.2)",
            maxWidth: "400px",
            // width: "100%",
            position: "relative",
            textAlign: "center",
            margin: "auto",
            zIndex: Number.MAX_SAFE_INTEGER,
          }}
        >
          <button
            onClick={onClose}
            style={{
              position: "absolute",
              top: "20px",
              right: "20px",
              background: "transparent",
              border: "none",
              fontSize: "26px",
              cursor: "pointer",
              color: "#495057",
              transition: "color 0.3s ease, transform 0.2s ease",
            }}
          >
            &times;
          </button>

          <div>
            <div
              style={{
                fontSize: "20px",
                fontWeight: "600",
                color: "#343a40",
                marginBottom: "20px",
              }}
            >
              {heading}
            </div>
            <div style={{ marginBottom: "30px" }}>
              {subHeading && (
                <p
                  style={{
                    fontSize: "14px",
                    color: "#495057",
                    marginBottom: "25px",
                  }}
                >
                  {subHeading}
                </p>
              )}
              {/* {isOtpVerified && redirectText && <p>{redirectText}</p>} */}
              {showMaxRetryLimitReachedTxt && <p>{CODK_MAX_RETRY_TEXT}</p>}

              <PhoneInputBox handlePhoneSubmitSms={handlePhoneSubmitSms} />
              {error && (
                <p
                  style={{
                    color: "red",
                    marginBottom: "20px",
                    fontSize: "14px",
                  }}
                >
                  {error}
                </p>
              )}
            </div>
            <div style={{ display: "flex", flexDirection: "column" }}>
              <button
                onClick={() => handlePhoneSubmitSms()}
                disabled={!isCartReady}
                style={{
                  padding: "15px 0",
                  backgroundColor: prePrimaryButtonColor || "#007bff",
                  color: prePrimaryButtonFontColor || "white",
                  boxShadow: "0 5px 15px rgba(82, 82, 84, 0.207)",
                  fontSize: "16px",
                  fontWeight: "600",
                  letterSpacing: "0.5px",
                  borderRadius: "8px",
                  marginBottom: "15px",
                  cursor: "pointer",
                  transition:
                    "background-color 0.3s ease, box-shadow 0.3s ease, transform 0.2s ease",
                }}
              >
                {isSmsLoading
                  ? "Sending..."
                  : sendBtnText + " →" || "Get OTP →"}
              </button>

              {preWhatsappButton && (
                <button
                  onClick={() => {
                    if (phoneNumber.length >= 9) {
                      handlePhoneSubmitWhatsapp();
                    } else {
                      setError(PLEASE_ENTER_VALID_PHONE_NUMBER);
                    }
                  }}
                  disabled={!isCartReady}
                  style={{
                    padding: "15px 0",
                    backgroundColor: prePrimaryButtonColor || "#007bff",
                    color: prePrimaryButtonFontColor || "white",
                    boxShadow: "0 5px 15px rgba(82, 82, 84, 0.207)",
                    fontSize: "16px",
                    fontWeight: "600",
                    letterSpacing: "0.5px",
                    borderRadius: "8px",
                    marginBottom: "15px",
                    cursor: "pointer",
                    transition:
                      "background-color 0.3s ease, box-shadow 0.3s ease, transform 0.2s ease",
                  }}
                >
                  {isWhatsappLoading
                    ? "Sending..."
                    : preWhatsappButtonText + " →" || "Get WhatsApp OTP →"}
                </button>
              )}

              {showSkipBtn && (
                <button
                  onClick={handleSkip}
                  disabled={isLoading}
                  style={{
                    padding: "15px 0",
                    backgroundColor: preSecondaryButtonColor || "#f8f9fa",
                    color: preSecondaryButtonFontColor || "#6c757d",
                    fontSize: "16px",
                    fontWeight: "600",
                    letterSpacing: "0.5px",
                    borderRadius: "8px",
                    marginBottom: "15px",
                    cursor: "pointer",
                    transition:
                      "background-color 0.3s ease, box-shadow 0.3s ease, transform 0.2s ease",
                  }}
                >
                  {isSkipLoading
                    ? "Skipping..."
                    : skipBtnText + " →" || "Cancel →"}
                </button>
              )}
            </div>
          </div>
        </div>
      )}
      {step == 2 && (
        <div
          style={{
            background: "white",
            padding: "20px",
            borderRadius: "12px",
            boxShadow: "0 10px 40px rgba(0, 0, 0, 0.2)",
            maxWidth: "480px",
            // width: "100%",
            position: "relative",
            textAlign: "center",
            margin: "auto",
            zIndex: Number.MAX_SAFE_INTEGER,
          }}
        >
          <button
            onClick={onClose}
            style={{
              position: "absolute",
              top: "20px",
              right: "20px",
              background: "transparent",
              border: "none",
              fontSize: "26px",
              cursor: "pointer",
              color: "#495057",
              transition: "color 0.3s ease, transform 0.2s ease",
            }}
          >
            &times;
          </button>

          <div
            style={{
              fontSize: "20px",
              fontWeight: "600",
              color: "#343a40",
              marginBottom: "20px",
            }}
          >
            {VERIFY_MOBILE_NUMBER}
          </div>
          <div style={{ marginBottom: "30px" }}>
            <p
              style={{
                fontSize: "16px",
                color: "#495057",
                marginBottom: "25px",
              }}
            >
              {ENTER_CODE_SEND_TO}
              <b>
                +{phoneNumber}
                <span
                  style={{ cursor: "pointer", color: "blue" }}
                  onClick={onChangePhonNoBtnClick}
                >
                  &nbsp; <Edit size={16} />
                </span>
              </b>
            </p>
            {/* <Frame
              ref={iframeRef}
              style={{
                width: "100%",
                border: "none", // No border for a clean look
                height: "100px",
              }}
            >
              {" "}
              <div
                style={{
                  display: "flex",
                  justifyContent: "center",
                }}
              >
                <OtpInput
                  value={otp}
                  onChange={setOtp}
                  numInputs={4}
                  inputType="number"
                  renderSeparator={<span> </span>}
                  renderInput={(props) => (
                    <input
                      {...props}
                      style={{
                        width: "50px",
                        height: "50px",
                        border: "1px solid #ced4da",
                        borderRadius: "6px",
                        fontSize: "16px",
                        textAlign: "center",
                        color: "#495057",
                        margin: "0 8px",
                        transition:
                          "border-color 0.3s ease, box-shadow 0.3s ease",
                        outline: "none",
                        appearance: "none", // Remove appearance for modern browsers
                        MozAppearance: "textfield", // Firefox
                        WebkitAppearance: "none", // Safari and Chrome
                      }}
                    />
                  )}
                  shouldAutoFocus
                />
              </div>
            </Frame> */}
            <div
              style={{
                display: "flex",
                justifyContent: "center",
              }}
            >
              <OtpInput
                value={otp}
                onChange={setOtp}
                numInputs={4}
                inputType="number"
                renderSeparator={<span> </span>}
                renderInput={(props) => (
                  <input
                    {...props}
                    style={{
                      width: "50px",
                      height: "50px",
                      border: "1px solid #ced4da",
                      borderRadius: "6px",
                      fontSize: "16px",
                      textAlign: "center",
                      color: "#495057",
                      margin: "0 8px",
                      transition:
                        "border-color 0.3s ease, box-shadow 0.3s ease",
                      outline: "none",
                      appearance: "none", // Remove appearance for modern browsers
                      MozAppearance: "textfield", // Firefox
                      WebkitAppearance: "none", // Safari and Chrome
                    }}
                  />
                )}
                shouldAutoFocus
              />
            </div>
          </div>
          <div style={{ marginTop: "30px" }}>
            {error && (
              <p
                style={{
                  color: "red",
                  fontSize: "16px",
                  animation: "fadeIn 0.5s ease",
                }}
              >
                {error}
              </p>
            )}
            {/* {showServerErrorText && (
              <p
                style={{
                  color: "red",
                  fontSize: "16px",
                  animation: "fadeIn 0.5s ease",
                }}
              >
                {SERVER_ERROR_TEXT}
              </p>
            )} */}
            <div
              style={{
                fontSize: "14px",
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                color: "#34373a",
              }}
            >
              <p>
                {DID_NOT_RECEIVE_OTP_TEXT}
                00:
                {timer < 10 ? `0${timer}` : timer} &nbsp;
              </p>
              <p>
                {showResendLink && (
                  <span style={{ cursor: "pointer" }} onClick={handleResendOtp}>
                    {RESEND_LINK_TEXT || "Resend"}
                  </span>
                )}
              </p>
            </div>
            <button
              onClick={() => handleOtpSubmit("SMS")}
              // disabled={!isCartReady}
              style={{
                width: "100%",
                padding: "15px",
                fontSize: "16px",
                backgroundColor: prePrimaryButtonColor || "#f8f9fa",
                color: prePrimaryButtonFontColor || "#6c757d",
                borderRadius: "6px",
                cursor: "pointer",
                transition: "background-color 0.3s ease",
                border: "none",
              }}
            >
              {isLoading
                ? VERIFYING_TEXT + "..."
                : verifyBtnText + " →" || "Continue →"}
            </button>
          </div>
        </div>
      )}
      {/* {step === 3 && <ShippingAddress setStep={setStep} />}
      {step === 4 && <AddOrEditAddress setStep={setStep} />} */}
      {[3, 4, 5].includes(step) && <OtpVerifiedMessage onClose={onClose} />}
    </>
  );
};

export default OtpForm;
