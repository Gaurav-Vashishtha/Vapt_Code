function truthy(v) {
  if (v === true || v === "true" || v === 1 || v === "1") return true;
  return false;
}

/**
 * Critical setup sections derived from saved onboarding / settings (same flags as QuickOnboardingV2).
 */
export function getCustomSetupSections(setting, options = {}) {
  if (!setting || typeof setting !== "object") return [];

  const otpRaw = setting.enablePreOrderOtp ?? setting.enable_pre_order_otp;
  const otp =
    otpRaw === true ||
    otpRaw === "true" ||
    otpRaw === 1 ||
    otpRaw === "1";
  const partial = Boolean(
    setting.partialPaymentEnabled ?? setting.partial_payment_enabled,
  );
  const smsConfirmation = truthy(
    setting.confirmationSmsEnabled ?? setting.confirmation_sms_enabled,
  );
  const smsFulfilment = truthy(
    setting.enableFulfilmentMessage ?? setting.enable_fulfilment_message,
  );
  const smsAbandoned = truthy(
    setting.abandonedCartEnabled ?? setting.abandoned_cart_enabled,
  );
  const waConfirmation = truthy(
    setting.confirmationWhatsapp ?? setting.confirmation_whatsapp,
  );
  const waFulfilment = truthy(
    setting.fulfilmentWhatsapp ?? setting.fulfilment_whatsapp,
  );
  const waAbandoned = truthy(setting.acWhatsapp ?? setting.ac_whatsapp);
  const waCodVerification = truthy(
    setting.sendVerificationLinkOnly ?? setting.send_verification_link_only,
  );

  const hasEngagement =
    smsConfirmation ||
    smsFulfilment ||
    smsAbandoned ||
    waConfirmation ||
    waFulfilment ||
    waAbandoned ||
    waCodVerification;

  const sections = [];

  if (otp || partial) {
    sections.push({
      id: "popup",
      titleKey: "custom_setup.section_popup_title",
      subtitleKey: "custom_setup.section_popup_subtitle",
    });
  }

  if (otp) {
    sections.push({
      id: "pre_order_otp",
      titleKey: "custom_setup.section_pre_order_otp_title",
      subtitleKey: "custom_setup.section_pre_order_otp_subtitle",
    });
  }

  if (partial) {
    sections.push({
      id: "partial_payment",
      titleKey: "custom_setup.section_partial_title",
      subtitleKey: "custom_setup.section_partial_subtitle",
    });
  }

  // The COD Form is switched on outside `setting` (its own module flag), so the caller passes it.
  if (options.codFormOn) {
    sections.push({
      id: "cod_form",
      titleKey: "custom_setup.section_cod_form_title",
      subtitleKey: "custom_setup.section_cod_form_subtitle",
    });
  }

  if (hasEngagement) {
    sections.push({
      id: "engagement",
      titleKey: "custom_setup.section_engagement_title",
      subtitleKey: "custom_setup.section_engagement_subtitle",
      flags: {
        smsConfirmation,
        smsFulfilment,
        smsAbandoned,
        waConfirmation,
        waFulfilment,
        waAbandoned,
        waCodVerification,
      },
    });
  }

  return sections;
}
