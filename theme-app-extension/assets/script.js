import { debugLog } from "../../app/javascript/packs/Modal/utilities/otpUtils";

(function () {
  // avoid duplicate loading
  if (window.COD_OTP_BOX_LOADED) {
    return;
  } else {
    window.COD_OTP_BOX_LOADED = true;
  }

  function loadScript() {
    var script = document.createElement("script");
    script.src =
      "https://cod.birdchime.com/script.js?v=" + new Date().getTime();
    script.async = false;
    var head = document.getElementsByTagName("head")[0];
    head.insertBefore(script, head.lastChild);
  }

  try {
    setTimeout(function () {
      loadScript();
    }, 50);
  } catch (e) {
    debugLog("Error Loading OTP Box, Please reach out to us via chat bubble");
  }

  const checkoutSelectors =
    'div[class~="shopify-payment-button"],a[href="/checkout"], button[name="checkout"], input[name="checkout"], button[id="cart-checkout"], button[id="cart-sidebar-checkout"], button[class="mr-popup-offer-actions__checkout-button"] #checkout, #dynamic-checkout-cart, #checkout-main button[type="submit"], [data-step-footer] button[type="submit"], .step__footer button[type="submit"], .edit_checkout #continue_button, .cart__submit, .birdchime-disable-node';
  function disableCheckout() {
    debugLog("Disable checkout from extension called..." + window.location);
    if (window.location.href.includes("products")) {
      debugLog("Products page found returning");
      enableCheckout();
      return;
    }
    debugLog(
      " window.CODKingBlockEventListener" + window.CODKingBlockEventListener
    );
    if (window.CODKingBlockEventListener == undefined) {
      window.CODKingBlockEventListener = function (e) {
        if (e) {
          e.preventDefault();
          e.stopPropagation();
        }
      };
    }
    document.body.querySelectorAll(checkoutSelectors).forEach(function (node) {
      debugLog(node + "Attaching the event from extension...");
      //node.addEventListener('click',window.CODKingBlockEventListener)
      //window.CODKingBlockEventListener=preventDefaultCheckout
      //node.addEventListener('click', window.BirdchimeCheckoutEventListener , true);
      node.addEventListener("click", window.CODKingBlockEventListener, true);

      node.classList.add("birdchime-disable-node");
    });
  }

  function enableCheckout() {
    debugLog("Enable from extension");
    document.body.querySelectorAll(checkoutSelectors).forEach(function (node) {
      node?.removeEventListener("click", window?.CODKingBlockEventListener);
      node?.removeEventListener("click", window?.CODKingEventListener);
      node.classList.remove("birdchime-disable-node");
    });
  }

  try {
    document.addEventListener("DOMContentLoaded", function (event) {
      disableCheckout();
    });
  } catch (e) {
    enableCheckout();
  }
})();
