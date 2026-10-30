import { t } from "../i18n";

/* Admin-side names for field types, block types and text groups. Kept as
   literal t() calls so they reach en.json. */
export const fieldTypeName = (type) => {
  switch (type) {
    case "text":
      return t("designer.custom_type_text", "Text");
    case "textarea":
      return t("designer.custom_type_textarea", "Text area");
    case "select":
      return t("designer.custom_type_select", "Dropdown");
    case "radio":
      return t("designer.custom_type_radio", "Radio buttons");
    case "checkbox":
      return t("designer.custom_type_checkbox", "Checkbox");
    case "date":
      return t("designer.custom_type_date", "Date");
    case "tel":
      return t("designer.type_tel", "Phone");
    case "email":
      return t("designer.type_email", "Email");
    case "country":
      return t("designer.type_country", "Country");
    case "province":
      return t("designer.type_province", "State / province");
    case "city":
      return t("designer.type_city", "City");
    case "postal":
      return t("designer.type_postal", "Postal code");
    case "consent":
      return t("designer.type_consent", "Marketing consent");
    default:
      return type;
  }
};

export const blockName = (block) => {
  switch (block.type) {
    case "order_summary":
      return t("designer.block_order_summary", "Order summary");
    case "quantity_offer":
      return t("designer.block_quantity_offer", "Quantity offer");
    case "fields":
      return block.settings && block.settings.group === "address"
        ? t("designer.block_address", "Address fields")
        : t("designer.block_contact", "Contact fields");
    case "shipping":
      return t("designer.block_shipping", "Shipping options");
    case "bumps":
      return t("designer.block_bumps", "Order bumps");
    case "discount":
      return t("designer.block_discount", "Discount code");
    case "totals":
      return t("designer.block_totals", "Totals");
    case "submit":
      return t("designer.block_submit", "Submit button");
    case "rich_text":
      return t("designer.block_rich_text", "Rich text");
    case "image":
      return t("designer.block_image", "Image or GIF");
    case "trust_badges":
      return t("designer.block_trust_badges", "Trust badges");
    case "countdown":
      return t("designer.block_countdown", "Countdown timer");
    case "threshold_bar":
      return t("designer.block_threshold_bar", "Free shipping / gift progress bar");
    default:
      return block.type;
  }
};

export const textGroupName = (id) => {
  switch (id) {
    case "labels":
      return t("designer.texts_group_labels", "Field labels");
    case "placeholders":
      return t("designer.texts_group_placeholders", "Placeholders");
    case "errors":
      return t("designer.texts_group_errors", "Error messages");
    case "shipping":
      return t("designer.texts_group_shipping", "Shipping, discount and totals");
    case "submit":
      return t("designer.texts_group_submit", "Submit and exit");
    case "otp":
      return t("designer.texts_group_otp", "OTP step");
    case "payment":
      return t("designer.texts_group_payment", "Payment option, bumps and upsell");
    case "thank_you":
      return t("designer.texts_group_thank_you", "Thank-you");
    case "blocks":
      return t("designer.texts_group_blocks", "Content blocks");
    default:
      return t("designer.texts_group_general", "General");
  }
};

/** "label_first_name" → "Label first name" for keys without a nicer name. */
export const humanizeKey = (key) => {
  const text = String(key || "").replace(/_/g, " ").trim();
  return text.charAt(0).toUpperCase() + text.slice(1);
};
