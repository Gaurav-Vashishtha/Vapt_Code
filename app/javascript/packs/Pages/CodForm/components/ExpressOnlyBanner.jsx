import React from "react";
import { Banner, Box } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { PATHS } from "../constants";
import { t } from "../i18n";

/**
 * Shown on screens whose settings belong to Express checkout while the shop
 * runs COD Form mode (DSH-7). `variant="otp"` is the note on the OTP screen:
 * those settings also drive the form's OTP step.
 * Renders nothing unless the module is on for the shop and the mode is cod_form.
 */
const ExpressOnlyBanner = ({ variant = "express" }) => {
  const bootstrap = useCodFormBootstrap();
  if (!bootstrap || !bootstrap.moduleEnabled || bootstrap.mode !== "cod_form") return null;

  // The form's OTP is fully its own (Fraud protection): the OTP screen carries no note.
  if (variant === "otp") return null;
  if (variant === "otp-legacy") {
    return (
      <Box paddingBlockEnd="400">
        <Banner
          tone="info"
          title={t("express_only_banner.otp_title", "These OTP settings also apply to the COD Form")}
          action={{
            content: t("express_only_banner.otp_cta", "Open Fraud protection"),
            onAction: () => navigateTo(PATHS.fraud),
          }}
        >
          <p>
            {t(
              "express_only_banner.otp_body",
              "OTP on/off, channel and message templates set here drive the OTP step of the COD Form. When the form asks for OTP is set in Fraud protection.",
            )}
          </p>
        </Banner>
      </Box>
    );
  }

  return (
    <Box paddingBlockEnd="400">
      <Banner
        tone="info"
        title={t("express_only_banner.title", "These settings apply to Express checkout only")}
        action={{
          content: t("express_only_banner.cta", "Open Form designer"),
          onAction: () => navigateTo(PATHS.designer),
        }}
      >
        <p>
          {t(
            "express_only_banner.body",
            "COD Form is on for your store. To change how the COD Form looks, use Form designer.",
          )}
        </p>
      </Banner>
    </Box>
  );
};

export default ExpressOnlyBanner;
