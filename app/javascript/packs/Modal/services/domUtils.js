// domUtils.js
import { debugLog } from "../utilities/otpUtils";
import { modalCssSelectors, SELECTORS } from "../utilities/selectors";
import { shopifyAddToCartForBuyNow } from "./cartService";

// Check if an element matches any of the Shopify "Buy Now" button selectors
function isShopifyBuyNowButton(buttonElement) {
  if (!buttonElement) {
    return false;
  }

  const productButtonSelectors = SELECTORS.BUY_NOW;

  // Check if the button matches any of the selectors in productButtonSelectors
  const isBuyNowButton = productButtonSelectors.some((selector) =>
    buttonElement.matches(selector)
  );

  // Additional checks to see if it has classes or attributes related to "Buy Now"
  const isBuyNowClass =
    buttonElement.classList.contains("shopify-payment-button__button") &&
    buttonElement.classList.contains(
      "shopify-payment-button__button--unbranded"
    );

  const parentElement = buttonElement.closest("shopify-buy-it-now-button");

  const hasBuyNowAttributes =
    parentElement &&
    parentElement.hasAttribute("access-token") &&
    parentElement.hasAttribute("buyer-country") &&
    parentElement.hasAttribute("buyer-currency");

  return isBuyNowButton || isBuyNowClass || hasBuyNowAttributes;
}

export function checkShopifyBuyNowButtons(event) {
  const parentElement = event; // The element where the event was triggered
  const buttonSelectors = SELECTORS.BUY_NOW;

  const buttonElement = buttonSelectors
    .map((selector) => parentElement.querySelector(selector))
    .find((button) => button && isShopifyBuyNowButton(button));

  if (buttonElement) {
    debugLog('This is a Shopify "Buy it now" button:', buttonElement);
    return true;
  }

  debugLog('This is NOT a Shopify "Buy it now" button.');
  return false;
}

// Function to inject custom code (e.g., show a modal)
export const injectCustomCode = (openModal) => {
  debugLog("Injecting custom code and opening modal.");
  openModal();
};

// Module state read by several components. Exposed through a getter rather than
// an exported `let`, so the mutation happens in one place instead of consumers
// relying on live-binding semantics.
let isBuyNowButton = false;
export const getIsBuyNowButton = () => isBuyNowButton;

export const checkAndAddBuyNow = (clickedButton) => {
  isBuyNowButton = checkShopifyBuyNowButtons(clickedButton);
  debugLog("isBuyNowButton", isBuyNowButton);
  // adding the data in cart for buy now button
  // if (isBuyNowButton) {
  //   shopifyAddToCartForBuyNow();
  // }
};

export function forceZIndex() {
  modalCssSelectors.forEach((selector) => {
    document.querySelectorAll(selector).forEach((el) => {
      el.style.setProperty("z-index", "1000", "important");
    });
  });
}
