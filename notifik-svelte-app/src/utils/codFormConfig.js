// COD address-form config (labels, placeholders, GST field). Mirrors the React
// Modal implementation (Modal/utilities/otpUtils.js#getCodFormConfig and
// Modal/utilities/addressValidation.js) so both storefronts behave the same.

export const COD_FORM_DEFAULT_PLACEHOLDERS = {
  name: "e.g. Rahul Sharma",
  pincode: "e.g. 110001",
  city: "e.g. New Delhi",
  state: "e.g. Delhi",
  email: "e.g. rahul@gmail.com",
  address1: "e.g. MG Road, Sector 14",
  address2: "e.g. Flat 302, Green Apartments",
};

export const COD_FORM_DEFAULT_GST = {
  enabled: false,
  label: "GST Number",
  placeholder: "e.g. 22AAAAA0000A1Z5",
  required: false,
};

export const getCodFormConfig = (settings) => {
  const cfg = settings?.codFormConfig || settings?.cod_form_config || {};
  const labels = cfg.labels || {};
  const placeholders = cfg.placeholders || {};
  const gst = cfg.gst || {};
  return {
    labels: Object.fromEntries(
      Object.keys(COD_FORM_DEFAULT_PLACEHOLDERS).map((key) => [
        key,
        (labels[key] && String(labels[key]).trim()) || "",
      ]),
    ),
    placeholders: Object.fromEntries(
      Object.entries(COD_FORM_DEFAULT_PLACEHOLDERS).map(([key, fallback]) => [
        key,
        (placeholders[key] && String(placeholders[key]).trim()) || fallback,
      ]),
    ),
    gst: {
      enabled: gst.enabled === true,
      required: gst.required === true,
      label: (gst.label && String(gst.label).trim()) || COD_FORM_DEFAULT_GST.label,
      placeholder:
        (gst.placeholder && String(gst.placeholder).trim()) ||
        COD_FORM_DEFAULT_GST.placeholder,
    },
  };
};

// Indian GSTIN: 15 chars (2-digit state code, 10-char PAN, entity char, "Z", checksum).
export const isValidGSTIN = (value) =>
  /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(
    String(value || "").trim().toUpperCase(),
  );

export const validateGstField = (value, { required = false } = {}) => {
  const v = String(value || "").trim();
  if (!v) return required ? "GST number is required" : "";
  if (!isValidGSTIN(v)) return "Enter a valid 15-character GST number";
  return "";
};
