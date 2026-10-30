# frozen_string_literal: true

# Pre-order OTP UI customization has two halves with different entitlements.
#
# Checkout copy (ui_customization.texts) is available on every plan: a merchant
# rewording their own checkout is not a paid feature.
#
# Removing the COD King mark (ui_customization.branding.hide_footer_branding) is
# the paid half, and needs Pro or above. The footer's terms and privacy links
# live in the same branding hash but are the merchant's own policies, so they
# are editable on every plan like the copy. Gate both the write path (SettingsController) and the read
# path (lightweight settings payload) through here, so a plan downgrade stops
# shipping the white-label overrides to the storefront without destroying what
# the merchant saved.
module UiCustomizationPlanGuard
  BRANDING_PLAN_NAMES = %w[pro enterprise enterprise_plus].freeze

  # The only branding keys that white-label the widget. Everything else in
  # ui_customization.branding (terms_url, privacy_url) is on every plan.
  GATED_BRANDING_KEYS = %w[hide_footer_branding].freeze

  module_function

  # White-labelling: hiding the COD King name, logo and footer mark.
  def branding_allowed_for?(shop)
    return false if shop.blank?

    norm = shop.plan&.name.to_s.strip.downcase.tr(" ", "_")
    return false if norm.blank?

    BRANDING_PLAN_NAMES.include?(norm) || norm.include?("enterprise_plus")
  end

  # Custom checkout copy, on every plan.
  def texts_allowed_for?(_shop)
    true
  end
end
