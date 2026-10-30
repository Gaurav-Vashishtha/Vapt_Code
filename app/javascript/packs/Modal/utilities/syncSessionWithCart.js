// this function will sync the session storage with the cart
// it will be called when the page is loaded every time
// it will be called every time and check if the cart _otpVerifiedPhoneNumber is same as the session storage _otpVerifiedPhoneNumber
// if not same then update the session storage with the cart _otpVerifiedPhoneNumber
// it will be called every time and check if the cart _otpVerifiedPhoneNumber is same as the session storage _otpVerifiedPhoneNumber
// if not same then update the  cart _otpVerifiedPhoneNumber with the session storage _otpVerifiedPhoneNumber
//session storage is the ultimate source of truth
//it will check getSessionValue with key verifiedNumberData

//cart.js data will be called to check cart _otpVerifiedPhoneNumber
//condition 1: if session does not have verifiedNumberData do nothing
//condition 2: if session have verifiedNumberData and cart has _otpVerifiedPhoneNumber then do nothing
//condition 3: if session have verifiedNumberData and cart does not have _otpVerifiedPhoneNumber then update the cart (post request) with session verifiedNumberData.otpVerifiedPhoneNumber.

import { executePost, getCart } from "../services/otpService";
import { debugLog, getSessionValue } from "./otpUtils";

export function syncSessionWithCart() {
  getCart().then((cart) => {
    const session = getSessionValue("verifiedNumberData");

    // Condition 1: If session does not have verifiedNumberData, do nothing
    if (!session) {
      debugLog("Not verified number in session, no action needed");
    } else {
      // Condition 2: If session has verifiedNumberData and cart has _otpVerifiedPhoneNumber, do nothing
      if (cart.attributes._otpVerifiedPhoneNumber) {
        debugLog("Cart already has a verified phone number, no action needed");
      } else {
        // Condition 3: If session has verifiedNumberData and cart does not have _otpVerifiedPhoneNumber,
        // update the cart with session verifiedNumberData.otpVerifiedPhoneNumber
        debugLog("Updating cart with verified phone number from session");
        executePost({
          attributes: {
            _otpVerifiedPhoneNumber: session.otpVerifiedPhoneNumber,
          },
        })
          .then(() =>
            debugLog("Cart updated successfully after sync with session")
          )
          .catch((error) =>
            console.error("Error updating cart while sync with session:", error)
          );
      }
    }
  });
}
