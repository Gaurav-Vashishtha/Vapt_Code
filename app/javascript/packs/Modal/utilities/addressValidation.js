// Shopify-compatible address validation & normalization helpers.
// Shopify's MailingAddressInput requires a recognized province name, a valid
// country-specific zip, and an E.164 phone for the buyer identity to be
// accepted at checkout. These helpers enforce that for India (the only market
// this widget currently supports).

const DEFAULT_CALLING_CODE = "+91";

// Canonical Shopify province names for India (28 states + 8 union territories),
// plus common aliases the pincode lookup / users may produce, mapped to the
// exact spelling Shopify accepts.
export const INDIAN_PROVINCES = {
  "andaman and nicobar islands": "Andaman and Nicobar Islands",
  "andhra pradesh": "Andhra Pradesh",
  "arunachal pradesh": "Arunachal Pradesh",
  assam: "Assam",
  bihar: "Bihar",
  chandigarh: "Chandigarh",
  chhattisgarh: "Chhattisgarh",
  "dadra and nagar haveli and daman and diu":
    "Dadra and Nagar Haveli and Daman and Diu",
  "dadra and nagar haveli": "Dadra and Nagar Haveli and Daman and Diu",
  "daman and diu": "Dadra and Nagar Haveli and Daman and Diu",
  delhi: "Delhi",
  "nct of delhi": "Delhi",
  "new delhi": "Delhi",
  goa: "Goa",
  gujarat: "Gujarat",
  haryana: "Haryana",
  "himachal pradesh": "Himachal Pradesh",
  "jammu and kashmir": "Jammu and Kashmir",
  "jammu & kashmir": "Jammu and Kashmir",
  "j&k": "Jammu and Kashmir",
  jharkhand: "Jharkhand",
  karnataka: "Karnataka",
  kerala: "Kerala",
  ladakh: "Ladakh",
  lakshadweep: "Lakshadweep",
  "madhya pradesh": "Madhya Pradesh",
  maharashtra: "Maharashtra",
  manipur: "Manipur",
  meghalaya: "Meghalaya",
  mizoram: "Mizoram",
  nagaland: "Nagaland",
  odisha: "Odisha",
  orissa: "Odisha",
  puducherry: "Puducherry",
  pondicherry: "Puducherry",
  punjab: "Punjab",
  rajasthan: "Rajasthan",
  sikkim: "Sikkim",
  "tamil nadu": "Tamil Nadu",
  telangana: "Telangana",
  tripura: "Tripura",
  "uttar pradesh": "Uttar Pradesh",
  uttarakhand: "Uttarakhand",
  uttaranchal: "Uttarakhand",
  "west bengal": "West Bengal",
};

const provinceKey = (value) => String(value || "").trim().toLowerCase();

// Returns the canonical Shopify province name, or the trimmed input if unknown.
export const normalizeProvince = (value) =>
  INDIAN_PROVINCES[provinceKey(value)] || String(value || "").trim();

export const isValidProvince = (value) =>
  Object.prototype.hasOwnProperty.call(INDIAN_PROVINCES, provinceKey(value));

// Indian PIN codes are 6 digits and never start with 0.
export const isValidPincode = (value) =>
  /^[1-9][0-9]{5}$/.test(String(value || "").trim());

export const isValidEmail = (value) =>
  /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || "").trim());

// Indian GSTIN: 15 chars (2-digit state code, 10-char PAN, entity char, "Z", checksum).
export const isValidGSTIN = (value) =>
  /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(
    String(value || "").trim().toUpperCase()
  );

export const validateGstField = (value, { required = false } = {}) => {
  const v = String(value || "").trim();
  if (!v) return required ? "GST number is required" : "";
  if (!isValidGSTIN(v)) return "Enter a valid 15-character GST number";
  return "";
};

// Normalize a phone number to E.164 (e.g. +919876543210) so Shopify accepts it.
export const normalizePhoneE164 = (phone, callingCode = DEFAULT_CALLING_CODE) => {
  if (!phone) return "";
  let p = String(phone).replace(/[^\d+]/g, "");
  if (p.startsWith("+")) return p;
  p = p.replace(/^0+/, "");
  const cc = String(callingCode || DEFAULT_CALLING_CODE).replace(/[^\d]/g, "");
  if (cc && p.startsWith(cc) && p.length > 10) p = p.slice(cc.length);
  return `+${cc}${p}`;
};

// Split a single full-name field into Shopify's firstName / lastName.
export const splitFullName = (fullName) => {
  const parts = String(fullName || "").trim().split(/\s+/).filter(Boolean);
  const firstName = parts.shift() || "";
  const lastName = parts.join(" ");
  return { firstName, lastName };
};

// Per-field validation used for live (onChange) feedback. Returns an error
// string or "" when valid, matching the existing validateField contract.
export const validateAddressField = (name, value, { requireEmail = true } = {}) => {
  const v = String(value || "");
  switch (name) {
    case "fullName":
      if (!splitFullName(v).firstName) return "Full name is required";
      return "";
    case "pincode":
      if (!v.trim()) return "Pincode is required";
      if (!isValidPincode(v)) return "Enter a valid 6-digit pincode";
      return "";
    case "address1":
      if (!v.trim()) return "Address is required";
      return "";
    case "city":
      if (!v.trim()) return "City is required";
      return "";
    case "state":
      if (!v.trim()) return "State is required";
      if (!isValidProvince(v)) return "Enter a valid state";
      return "";
    case "email":
      if (!v.trim()) return requireEmail ? "Email is required" : "";
      if (!isValidEmail(v)) return "Invalid email format";
      return "";
    default:
      return "";
  }
};

// Validate the whole form at submit time. Returns an errors map.
export const validateAddressForm = (formData, options = {}) => ({
  fullName: validateAddressField("fullName", formData.fullName, options),
  pincode: validateAddressField("pincode", formData.pincode, options),
  address1: validateAddressField("address1", formData.address1, options),
  city: validateAddressField("city", formData.city, options),
  state: validateAddressField("state", formData.state, options),
  email: validateAddressField("email", formData.email, options),
});
