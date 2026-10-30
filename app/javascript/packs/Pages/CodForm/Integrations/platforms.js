import { FEATURES, P3_PIXEL_PLATFORMS } from "../constants";
import { t } from "../i18n";

/* Per-platform wording for the pixel screens (C.6, I.2). */
export const platformInfo = (platform) => {
  switch (platform) {
    case "meta":
      return {
        name: t("pixels.meta_name", "Meta Pixel"),
        idLabel: t("pixels.meta_id", "Pixel ID"),
        idPlaceholder: "1234567890123456",
        tokenLabel: t("pixels.meta_token", "Conversions API access token"),
        hasToken: true,
        hasTestCode: true,
      };
    case "tiktok":
      return {
        name: t("pixels.tiktok_name", "TikTok Pixel"),
        idLabel: t("pixels.tiktok_id", "Pixel code"),
        idPlaceholder: "C4ABCDEF123",
        tokenLabel: t("pixels.tiktok_token", "Events API access token"),
        hasToken: true,
        hasTestCode: true,
      };
    case "ga4":
      return {
        name: t("pixels.ga4_name", "Google Analytics 4"),
        idLabel: t("pixels.ga4_id", "Measurement ID"),
        idPlaceholder: "G-XXXXXXXXXX",
        tokenLabel: t("pixels.ga4_token", "Measurement Protocol API secret"),
        hasToken: true,
        hasTestCode: false,
      };
    case "google_ads":
      return {
        name: t("pixels.google_ads_name", "Google Ads"),
        idLabel: t("pixels.google_ads_id", "Conversion ID"),
        idPlaceholder: "AW-123456789",
        tokenLabel: "",
        hasToken: false,
        hasTestCode: false,
        hasConversionLabel: true,
      };
    case "snapchat":
      return {
        name: t("pixels.snapchat_name", "Snapchat Pixel"),
        idLabel: t("pixels.snapchat_id", "Pixel ID"),
        idPlaceholder: "",
        tokenLabel: t("pixels.snapchat_token", "Conversions API token"),
        hasToken: true,
        hasTestCode: false,
      };
    default:
      return {
        name: t("pixels.pinterest_name", "Pinterest Tag"),
        idLabel: t("pixels.pinterest_id", "Tag ID"),
        idPlaceholder: "",
        tokenLabel: t("pixels.pinterest_token", "Conversions API token"),
        hasToken: true,
        hasTestCode: false,
        hasAdAccount: true,
      };
  }
};

export const pixelIdError = (platform, value) => {
  const id = String(value || "").trim();
  if (!id) return t("pixels.error_id_required", "Enter the ID.");
  if (platform === "ga4" && !/^G-[A-Z0-9]+$/i.test(id)) return t("pixels.error_ga4", "A measurement ID looks like G-XXXXXXXXXX.");
  if (platform === "google_ads" && !/^AW-\d+$/i.test(id)) return t("pixels.error_google_ads", "A conversion ID looks like AW-123456789.");
  if ((platform === "meta" || platform === "snapchat") && id.length < 6) return t("pixels.error_id_short", "This ID looks too short.");
  return undefined;
};

/** Gate that applies to adding one more pixel of `platform` given the current list. */
export const gateForNewPixel = (platform, pixels) => {
  if (P3_PIXEL_PLATFORMS.includes(platform)) return FEATURES.PIXELS_P3;
  const existing = (pixels || []).filter((pixel) => pixel.platform === platform).length;
  return existing >= 1 ? FEATURES.EXTRA_PIXELS : FEATURES.FIRST_PIXEL;
};
