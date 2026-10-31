/**
 * Persistent sign-in storage: encrypts and stores OTP verification + shipping addresses
 * in localStorage when setting persistent_signin is true, so users don't need to
 * re-verify OTP on every new tab/session.
 *
 * Storage is not tied to shop: a single key is used (no shop domain in key).
 * When persistent_signin is enabled we use this data; when disabled we ignore it and always ask for OTP.
 *
 * Uses Web Crypto API (AES-GCM) with a fixed derivation (no shop information).
 */

import { setCustomerEmail } from "./sessionService.js";

const STORAGE_KEY = "codk_persistent_signin";
const PAYLOAD_VERSION = 1;
const SALT = "codk_persistent_signin_v1";
const IV_LENGTH = 12;
const KEY_LENGTH = 256;
const PBKDF2_ITERATIONS = 100000;

/** Single key for all shops; no shop domain in storage. */
function getStorageKey() {
  return STORAGE_KEY;
}

/**
 * Derive a CryptoKey using a fixed secret (no shop domain).
 * @returns {Promise<CryptoKey>}
 */
async function deriveKey() {
  const enc = new TextEncoder();
  const password = enc.encode(SALT);
  const salt = enc.encode(SALT);
  const imp = await crypto.subtle.importKey(
    "raw",
    password,
    "PBKDF2",
    false,
    ["deriveBits", "deriveKey"]
  );
  return crypto.subtle.deriveKey(
    {
      name: "PBKDF2",
      salt,
      iterations: PBKDF2_ITERATIONS,
      hash: "SHA-256",
    },
    imp,
    { name: "AES-GCM", length: KEY_LENGTH },
    false,
    ["encrypt", "decrypt"]
  );
}

/**
 * Encrypt plaintext (string) with AES-GCM.
 * @param {string} plaintext
 * @param {CryptoKey} key
 * @returns {Promise<string>} base64(iv + ciphertext)
 */
async function encrypt(plaintext, key) {
  const enc = new TextEncoder();
  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, tagLength: 128 },
    key,
    enc.encode(plaintext)
  );
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(ciphertext), iv.length);
  return btoa(String.fromCharCode(...combined));
}

/**
 * Decrypt payload (base64 string) with AES-GCM.
 * @param {string} base64Payload
 * @param {CryptoKey} key
 * @returns {Promise<string>} plaintext
 */
async function decrypt(base64Payload, key) {
  const raw = Uint8Array.from(atob(base64Payload), (c) => c.charCodeAt(0));
  const iv = raw.slice(0, IV_LENGTH);
  const ciphertext = raw.slice(IV_LENGTH);
  const dec = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv, tagLength: 128 },
    key,
    ciphertext
  );
  return new TextDecoder().decode(dec);
}

/**
 * Check if persistent sign-in is enabled from settings.
 * @param {Object|null} settings - settingSession (camelCase or snake_case)
 * @returns {boolean}
 */
export function isPersistentSigninEnabled(settings) {
  if (!settings || typeof settings !== "object") return false;
  return (
    settings.persistentSignin === true ||
    settings.persistent_signin === true
  );
}

/**
 * Build payload to persist (verified state + addresses + related session keys).
 * @param {Object} sessionSnapshot - from getSessionValue for each key
 * @returns {Object}
 */
export function buildPersistentPayload(sessionSnapshot) {
  return {
    version: PAYLOAD_VERSION,
    savedAt: Date.now(),
    verifiedNumberData: sessionSnapshot.verifiedNumberData ?? null,
    preOrderOtpResponse: sessionSnapshot.preOrderOtpResponse ?? null,
    shipping_addresses: sessionSnapshot.shipping_addresses ?? null,
    customer_email: sessionSnapshot.customer_email ?? null,
    customer_id: sessionSnapshot.customer_id ?? null,
    cod_king_selected_address: sessionSnapshot.cod_king_selected_address ?? null,
  };
}

/**
 * Save persistent sign-in data to localStorage (encrypted).
 * No-op if persistent_signin is false. Storage key is not tied to shop.
 * @param {string} [_shopDomain] - unused; kept for API compatibility
 * @param {Object} settings - settingSession
 * @param {Object} payload - from buildPersistentPayload
 * @returns {Promise<boolean>}
 */
export async function savePersistentData(_shopDomain, settings, payload) {
  if (typeof window === "undefined" || !window.localStorage) return false;
  if (!isPersistentSigninEnabled(settings)) return false;

  try {
    const key = await deriveKey();
    const plaintext = JSON.stringify(payload);
    const encrypted = await encrypt(plaintext, key);
    localStorage.setItem(getStorageKey(), encrypted);
    return true;
  } catch (e) {

    return false;
  }
}

/**
 * Load and decrypt persistent sign-in data from localStorage.
 * @param {string} shopDomain
 * @param {Object} settings - settingSession
 * @returns {Promise<Object|null>} Decrypted payload or null
 */
export async function loadPersistentData(shopDomain, settings) {
  if (typeof window === "undefined" || !window.localStorage) return null;
  if (!isPersistentSigninEnabled(settings)) return null;
  if (!shopDomain) return null;

  try {
    const storageKey = getStorageKey();
    const stored = localStorage.getItem(storageKey);
    if (!stored) return null;

    const key = await deriveKey();
    const plaintext = await decrypt(stored, key);
    const payload = JSON.parse(plaintext);
    if (payload?.version !== PAYLOAD_VERSION) return null;
    if (!payload.verifiedNumberData?.isOTPVerified) return null;
    return payload;
  } catch (e) {

    return null;
  }
}

/**
 * Clear persistent sign-in data (e.g. on logout). Key is not tied to shop.
 * @param {string} [_shopDomain] - unused; kept for API compatibility
 * @returns {void}
 */
export function clearPersistentData(_shopDomain) {
  if (typeof window === "undefined" || !window.localStorage) return;
  localStorage.removeItem(getStorageKey());
}

/**
 * Restore session from persistent data: write all keys to sessionStorage and return
 * what the app store should update (phoneNumber, countryCode, preOrderOtpResponse, addresses).
 * @param {Object} payload - from loadPersistentData
 * @param {Function} setSessionValue - (key, value) => void
 * @returns {{ phoneNumber: string, countryCode: string, countryCallingCode: string, preOrderOtpResponse: object|null, addresses: array }|null}
 */
export function restoreSessionFromPayload(payload, setSessionValue) {
  if (!payload) return null;

  setSessionValue("verifiedNumberData", payload.verifiedNumberData ?? null);
  setSessionValue("preOrderOtpResponse", payload.preOrderOtpResponse ?? null);
  setSessionValue("shipping_addresses", payload.shipping_addresses ?? []);
  if (payload.customer_email != null) setCustomerEmail(payload.customer_email);
  if (payload.customer_id != null) setSessionValue("customer-id", payload.customer_id);
  if (payload.cod_king_selected_address != null) {
    setSessionValue("cod_king_selected_address", payload.cod_king_selected_address);
  }

  const v = payload.verifiedNumberData || {};
  return {
    phoneNumber: v.otpVerifiedPhoneNumber || "",
    countryCode: v.countryCode || "91",
    countryCallingCode: v.countryCallingCode || "+91",
    preOrderOtpResponse: payload.preOrderOtpResponse || null,
    addresses: Array.isArray(payload.shipping_addresses) ? payload.shipping_addresses : [],
  };
}

/**
 * Load persistent data (if enabled), restore to session and update app store.
 * When persistent_signin is disabled we do not use stored data; OTP flow runs as normal.
 * Call after settings are available (e.g. in main.js after fetchSettings).
 * @param {Object} settings - settingSession (camelCase)
 * @param {string} shopDomain
 * @param {Object} deps - { setSessionValue, appStore, actions }
 * @returns {Promise<boolean>} true if restore was performed
 */
export async function restorePersistentSigninIfEnabled(settings, shopDomain, deps) {
  const { setSessionValue, appStore, actions } = deps;
  if (!isPersistentSigninEnabled(settings) || !shopDomain) return false;
  const payload = await loadPersistentData(shopDomain, settings);
  if (!payload) return false;

  const restored = restoreSessionFromPayload(payload, setSessionValue);
  if (!restored) return false;

  appStore.update((state) => ({
    ...state,
    phoneNumber: restored.phoneNumber,
    countryCode: restored.countryCode,
    countryCallingCode: restored.countryCallingCode,
    preOrderOtpResponse: restored.preOrderOtpResponse,
    settings: settings || state.settings,
  }));
  if (restored.addresses?.length) {
    actions.setAddresses(restored.addresses);
  }
  return true;
}
