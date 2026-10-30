import { FEATURES, LIMITS } from "../constants";
import { t } from "../i18n";

/* One entry per offer kind: route segment, API offer_type, gate, limits. */
export const OFFER_SEGMENTS = ["quantity", "bundles", "bumps", "pre-upsells", "upsells", "downsells", "thresholds"];

export const offerMeta = (segment) => {
  switch (segment) {
    case "quantity":
      return {
        segment,
        offerType: "quantity",
        feature: FEATURES.QUANTITY_OFFERS,
        activeLimit: LIMITS.ACTIVE_QUANTITY_OFFERS,
        title: t("offers.quantity_title", "Quantity offers"),
        description: t("offers.quantity_desc", "Buy more, save more: tiers with a percentage, a fixed discount or a fixed unit price."),
        newLabel: t("offers.quantity_new", "Add quantity offer"),
        limitText: t("offers.quantity_limit", "You can have up to 50 active quantity offers."),
      };
    case "bumps":
      return {
        segment,
        offerType: "bump",
        feature: FEATURES.ORDER_BUMPS,
        activeLimit: LIMITS.ACTIVE_BUMPS,
        title: t("offers.bumps_title", "Order bumps"),
        description: t("offers.bumps_desc", "A small add-on the buyer can tick inside the form."),
        newLabel: t("offers.bumps_new", "Add order bump"),
        limitText: t("offers.bumps_limit", "You can have up to 20 active order bumps. A form shows the first 3 that match."),
      };
    case "bundles":
      return {
        segment,
        offerType: "bundle",
        feature: FEATURES.QUANTITY_OFFERS,
        activeLimit: null,
        title: t("offers.bundles_title", "Bundles"),
        description: t("offers.bundles_desc", "Sell 2 to 6 products together with a discount on the set, on the product page and in the form."),
        newLabel: t("offers.bundles_new", "Add bundle"),
        limitText: "",
      };
    case "pre-upsells":
      return {
        segment,
        offerType: "pre_upsell",
        feature: FEATURES.ORDER_BUMPS,
        activeLimit: null,
        title: t("offers.pre_upsells_title", "Pre-purchase upsells"),
        description: t("offers.pre_upsells_desc", "A popup after Complete order: when the cart has these products, offer those, with or without a discount."),
        newLabel: t("offers.pre_upsells_new", "Add pre-purchase upsell"),
        limitText: "",
      };
    case "upsells":
      return {
        segment,
        offerType: "upsell",
        feature: FEATURES.UPSELL,
        activeLimit: null,
        title: t("offers.upsells_title", "One-click upsells"),
        description: t("offers.upsells_desc", "Offer one more product right after the order. Accepting adds it to the same order."),
        newLabel: t("offers.upsells_new", "Add upsell"),
        limitText: "",
      };
    case "downsells":
      return {
        segment,
        offerType: "downsell",
        feature: FEATURES.DOWNSELL,
        activeLimit: LIMITS.ACTIVE_DOWNSELLS,
        title: t("offers.downsells_title", "Downsell on close"),
        description: t("offers.downsells_desc", "A discount shown once when the buyer tries to close the form."),
        newLabel: t("offers.downsells_new", "Add downsell"),
        limitText: t("offers.downsells_limit", "Only one downsell can be active at a time."),
      };
    case "thresholds":
      return {
        segment,
        offerType: "threshold",
        feature: FEATURES.THRESHOLD_OFFERS,
        activeLimit: null,
        title: t("offers.thresholds_title", "Free shipping and gift thresholds"),
        description: t("offers.thresholds_desc", "A progress bar towards free shipping or a free gift."),
        newLabel: t("offers.thresholds_new", "Add threshold"),
        limitText: "",
      };
    default:
      return null;
  }
};

export const segmentForType = (offerType) =>
  OFFER_SEGMENTS.find((segment) => offerMeta(segment).offerType === offerType) || "quantity";

export const statusLabel = (status) => {
  switch (status) {
    case "active":
      return t("offers.status_active", "Active");
    case "paused":
      return t("offers.status_paused", "Paused");
    case "archived":
      return t("offers.status_archived", "Archived");
    default:
      return t("offers.status_draft", "Draft");
  }
};

export const statusTone = (status) => (status === "active" ? "success" : status === "paused" ? "attention" : undefined);

export const discountTypeLabel = (type) => {
  switch (type) {
    case "percentage":
      return t("offers.discount_percentage", "Percentage off");
    case "fixed_amount":
      return t("offers.discount_fixed_amount", "Fixed amount off");
    case "unit_price":
      return t("offers.discount_unit_price", "Fixed price per unit");
    case "fixed_price":
      return t("offers.discount_fixed_price", "Fixed price");
    default:
      return t("offers.discount_none", "No discount");
  }
};
