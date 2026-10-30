/**
 * Navigation Utilities
 *
 * Simple centralized navigation functions
 * Back navigation goes to whatever the previous screen was
 */

import { get } from "svelte/store";
import { appStore, actions } from "../stores/buttonManager.js";
import { closeModalAndNotifyParent } from "./helpers.js";
import {
  getSessionValue,
  getShippingAddresses,
} from "../services/sessionService.js";

const DEBUG_MODE = true;
/**
 * Simple back navigation handler
 * Navigates to the previous screen that was opened
 * If no previous screen (or on phone screen), closes the modal
 *
 * @param {Object} [options={}] - Optional configuration
 * @param {Function} [options.closeModalAction] - Custom closeModal action (defaults to actions.closeModal)
 * @param {Function} [options.setScreenAction] - Custom setScreen action (defaults to actions.setScreen)
 * @returns {void}
 */
export const handleBackNavigation = (options = {}) => {
  const {
    closeModalAction = actions.closeModal,
    setScreenAction = actions.setScreen,
  } = options;

  const state = get(appStore);
  const currentScreen = state?.currentScreen || "phone";
  let previousScreen = state?.previousScreen;

  // ⚡ CRITICAL: Never navigate to OTP screen on back action
  // If previous screen is OTP, go directly to phone screen instead
  // OTP is a verification screen - if going back, user wants to edit phone number
  if (previousScreen === "otp") {
    previousScreen = "phone";
  }

  // ⚡ CRITICAL: Prevent loop - Address screen should never go back to Payment
  // Address comes before Payment in the flow, so going back from Address should go to OTP/Phone
  // If previous screen is payment and current is address, go to phone instead (OTP redirects to phone anyway)
  if (currentScreen === "address" && previousScreen === "payment") {
    previousScreen = "phone";
  }

  // ⚡ CRITICAL: Prevent loop when going back from address-form to address with no addresses
  // If previous screen is "address" and there are no addresses, skip address selection
  // (which would immediately open add form again) and go to phone instead
  if (currentScreen === "address-form" && previousScreen === "address") {
    const addresses = getShippingAddresses() || state.addresses || [];
    const addressCount = Array.isArray(addresses) ? addresses.length : 0;

    if (addressCount === 0) {
      // Set previousScreen to phone so we navigate there instead
      previousScreen = "phone";
    } else {
    }
  }

  // ⚡ ADDITIONAL SAFEGUARD: Also prevent navigating TO address screen if there are no addresses
  // This catches the case where navigationUtils redirects to "address" but we want to skip it
  if (previousScreen === "address") {
    const addresses = getShippingAddresses() || state.addresses || [];
    const addressCount = Array.isArray(addresses) ? addresses.length : 0;
    if (addressCount === 0 && currentScreen === "address-form") {
      // We're already handling this above, but this is a backup check
      previousScreen = "phone";
    }
  }

  // If no previous screen or on phone screen, close modal
  if (!previousScreen || currentScreen === "phone") {
    closeModalAndNotifyParent(closeModalAction, false);
    return;
  }

  // Navigate to previous screen (or phone if it was OTP)
  setScreenAction(previousScreen);
};
