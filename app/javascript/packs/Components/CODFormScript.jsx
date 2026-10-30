import React, { useState, useCallback, useRef, useEffect } from "react";
import "./application.css";
import CartOTPWidget from "./CartOTPWidget";
import SuccessMessage from "./SuccessMessage";
import axios from "axios";
// import ReactDOM from "react-dom";
import { createRoot } from "react-dom/client";
import { debugLog } from "../Modal/utilities/otpUtils";

const CODForm = ({ enableCheckOutFn, disableCheckoutFn, checkoutBtns }) => {
  const [showModal, setShowModal] = useState(false);
  const [modalToggleClass, setModalToggleClass] = useState(
    "codk-modal-inactive"
  );
  const refOne = useRef(null);

  useEffect(() => {
    //document.addEventListener("click", handleCLickOutside, true);
    debugLog("adding eventListener");
    checkoutBtns.forEach((btn) => {
      btn.addEventListener("click", handleClick, true);
      window.CODKingEventListener = handleClick;
      btn.addEventListener("click", window.CODKingBlockEventListener, true);
      debugLog("Adding eventListener" + btn);
    });
  }, []);

  const handleClick = useCallback(async () => {
    toggleModal();
    debugLog("handleClick");
  }, [showModal, modalToggleClass]);

  const toggleModal = useCallback(() => {
    debugLog("toggleModal");
    if (showModal) {
      setShowModal(false);
      setModalToggleClass("codk-modal-inactive");
    } else {
      setShowModal(true);
      setModalToggleClass("codk-modal-active");
    }
    debugLog("toggleModalComplete");
  }, [showModal, modalToggleClass]);

  const handleClose = useCallback(() => {
    let node = document.querySelector(`#codk-otp-widget-box`);
    axios.get(`${window.Shopify.routes.root}cart.js`).then((response) => {
      if (response.status === 200) {
        if (response.data.attributes.isCodkOtpVerifed) {
          debugLog("7777777");
          enableCheckOutFn();
          // ReactDOM.render(<SuccessMessage />, node);
          const root = createRoot(node);
          root.render(<SuccessMessage />);
          setTimeout(function () {
            window.location.href = "/checkout";
          }, 2000); //will call the function after 2 secs.

          return;
        }
      }
    });

    setShowModal(false);
    setModalToggleClass("codk-modal-inactive");
    debugLog("handleClose");
  }, [showModal, modalToggleClass]);

  return (
    <>
      {/* Modal code start */}
      {showModal ? (
        <div id="" className={modalToggleClass} ref={refOne}>
          <div className="codk-modal-content">
            <span onClick={handleClose} className="close mc-ch-elem">
              X
            </span>
            <CartOTPWidget
              enableCheckOutFn={enableCheckOutFn}
              disableCheckoutFn={disableCheckoutFn}
            />
          </div>
        </div>
      ) : null}
      {/* Modal code Ends */}
    </>
  );
};

const CODFormScriptContainer = ({
  enableCheckOutFn,
  disableCheckoutFn,
  checkoutBtns,
}) => {
  debugLog("BirdC hello");
  if (
    window?.location?.pathname?.includes("/products") ||
    window?.location?.pathname?.includes("/cart")
  ) {
    return (
      <>
        <CODForm
          enableCheckOutFn={enableCheckOutFn}
          disableCheckoutFn={disableCheckoutFn}
          checkoutBtns={checkoutBtns}
        />
      </>
    );
  }
};

export default CODFormScriptContainer;
