import { t } from "../i18n";

/* Rejection reason codes (E.3, E.9) → merchant wording. */
export const REASON_CODES = [
  "phone_blocked", "email_blocked", "ip_blocked", "phone_limit", "email_limit", "ip_limit",
  "max_quantity", "honeypot", "too_fast", "zip_not_allowed", "country_not_allowed",
  "province_not_allowed", "product_not_allowed", "collection_not_allowed", "vendor_not_allowed",
  "total_out_of_range", "rto_high",
];

export const reasonLabel = (code) => {
  switch (code) {
    case "phone_blocked":
      return t("fraud.reason_phone_blocked", "Phone on your block list");
    case "email_blocked":
      return t("fraud.reason_email_blocked", "Email on your block list");
    case "ip_blocked":
      return t("fraud.reason_ip_blocked", "IP address on your block list");
    case "phone_limit":
      return t("fraud.reason_phone_limit", "Too many orders from this phone");
    case "email_limit":
      return t("fraud.reason_email_limit", "Too many orders from this email");
    case "ip_limit":
      return t("fraud.reason_ip_limit", "Too many orders from this IP address");
    case "max_quantity":
      return t("fraud.reason_max_quantity", "Quantity above your maximum");
    case "honeypot":
      return t("fraud.reason_honeypot", "Suspected bot (hidden field filled)");
    case "too_fast":
      return t("fraud.reason_too_fast", "Suspected bot (submitted too fast)");
    case "zip_not_allowed":
      return t("fraud.reason_zip_not_allowed", "Postal code not allowed for COD");
    case "country_not_allowed":
      return t("fraud.reason_country_not_allowed", "Country not allowed for COD");
    case "province_not_allowed":
      return t("fraud.reason_province_not_allowed", "State / province not allowed for COD");
    case "product_not_allowed":
      return t("fraud.reason_product_not_allowed", "Product not allowed for COD");
    case "collection_not_allowed":
      return t("fraud.reason_collection_not_allowed", "Collection not allowed for COD");
    case "vendor_not_allowed":
      return t("fraud.reason_vendor_not_allowed", "Vendor not allowed for COD");
    case "total_out_of_range":
      return t("fraud.reason_total_out_of_range", "Order total outside your COD range");
    case "rto_high":
      return t("fraud.reason_rto_high", "High return risk");
    default:
      return code;
  }
};

export const stageLabel = (stage) => {
  switch (stage) {
    case "session":
      return t("fraud.stage_session", "Opening the form");
    case "quote":
      return t("fraud.stage_quote", "Filling the form");
    case "order":
      return t("fraud.stage_order", "Placing the order");
    case "otp":
      return t("fraud.stage_otp", "OTP");
    default:
      return stage || "";
  }
};
