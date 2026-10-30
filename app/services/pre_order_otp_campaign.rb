# frozen_string_literal: true

# Free pre-order OTP campaign (India). Everything is ENV-driven so the
# campaign can be turned on/off and re-dated without a deploy:
#
#   PRE_ORDER_OTP_CAMPAIGN_START_DATE  e.g. "2026-07-15"
#   PRE_ORDER_OTP_CAMPAIGN_END_DATE    e.g. "2026-08-15"
#   PRE_ORDER_OTP_CAMPAIGN_COUPON_CODE e.g. "FREEOTP2026"
#
# A shop redeems the coupon on the subscription page. Eligibility:
#   1. Installed between start and end date (uses the Shop's created_at).
#   2. Not uninstalled after the start date (uninstalled_shops rows are the
#      canonical uninstall record — UninstallNewJob destroys the Shop row and
#      writes one, so any row at/after start means a reinstall trying to game
#      the window).
#
# Redeemed shops get pre-order OTPs to India (country_code IN) for free:
# PricingJobs::DynamicChargeJob marks those PreOrderOtp rows charged at $0.
module PreOrderOtpCampaign
  module_function

  FREE_COUNTRY_CODE = 'IN'

  def coupon_code
    ENV['PRE_ORDER_OTP_CAMPAIGN_COUPON_CODE'].to_s.strip
  end

  def start_date
    parse_date(ENV['PRE_ORDER_OTP_CAMPAIGN_START_DATE'])
  end

  def end_date
    parse_date(ENV['PRE_ORDER_OTP_CAMPAIGN_END_DATE'])
  end

  def configured?
    coupon_code.present? && start_date.present? && end_date.present?
  end

  # Campaign window (inclusive). Coupons can only be applied while active.
  def active?
    configured? && Time.current.between?(start_date.beginning_of_day, end_date.end_of_day)
  end

  def applied?(shop)
    shop.present? &&
      shop.otp_campaign_coupon_applied_at.present? &&
      shop.otp_campaign_coupon_code.to_s.casecmp?(coupon_code)
  end

  # Redeemed shops send pre-order OTPs to India for free.
  def free_otp_for_shop?(shop)
    configured? && applied?(shop)
  end

  # nil when the shop may apply `code`; otherwise a merchant-facing error.
  def eligibility_error(shop, code)
    return 'This coupon is not currently available.' unless configured?
    return 'Invalid coupon code.' unless code.to_s.strip.casecmp?(coupon_code)
    return 'Coupon already applied.' if applied?(shop)
    return 'This coupon has expired.' unless active?

    installed_at = shop.created_at
    unless installed_at.present? &&
           installed_at.between?(start_date.beginning_of_day, end_date.end_of_day)
      return 'This coupon is only available for stores installed during the campaign period.'
    end

    if uninstalled_after_start?(shop)
      return 'This coupon is not available for stores that uninstalled the app during the campaign period.'
    end

    nil
  end

  def apply!(shop, code)
    error = eligibility_error(shop, code)
    return error if error

    shop.update!(
      otp_campaign_coupon_code: coupon_code,
      otp_campaign_coupon_applied_at: Time.current
    )
    nil
  end

  def remove!(shop)
    shop.update!(
      otp_campaign_coupon_code: nil,
      otp_campaign_coupon_applied_at: nil
    )
    nil
  end

  def status_for(shop)
    {
      configured: configured?,
      active: active?,
      applied: applied?(shop),
      start_date: start_date&.iso8601,
      end_date: end_date&.iso8601,
      applied_at: shop&.otp_campaign_coupon_applied_at&.iso8601
    }
  end

  def uninstalled_after_start?(shop)
    UninstalledShop
      .where(shop_domain: shop.shopify_domain)
      .where('created_at >= ?', start_date.beginning_of_day)
      .exists?
  end

  def parse_date(value)
    return nil if value.to_s.strip.blank?
    Date.parse(value.to_s.strip)
  rescue ArgumentError
    nil
  end
end
