class PreOrderOtp < ApplicationRecord
  # Session restored from persistent sign-in / SSO: the shopper verified earlier, so no OTP was sent.
  # The row exists only so abandonment, reminders and draft orders see the cart. It is never charged
  # (status nil, is_charged true, no wallet deduction) and is left out of OTP logs and counts (otp_sends).
  PERSISTENT_SIGNIN = 'PERSISTENT_SIGNIN'.freeze
  PERSISTENT_SIGNIN_LOCK_TTL = 30 # seconds

  belongs_to :shop

  scope :otp_sends, -> { where.not(ver_type: PERSISTENT_SIGNIN) }

  after_create :update_wallet_balance, unless: :persistent_signin?

  def persistent_signin?
    ver_type == PERSISTENT_SIGNIN
  end

  # Creates the row for a restored session that has none yet. sso_token is the JWT issued when the
  # number was OTP-verified (SsoJwtService); without a valid one nothing is created, so this public
  # endpoint can't be used to start reminders to arbitrary numbers. Returns the row or nil.
  def self.ensure_for_persistent_signin(shop, device_id:, sso_token:, cart_details:)
    return nil if shop.blank? || device_id.blank? || sso_token.blank?
    return nil if where(device_id: device_id).exists?

    claims = SsoJwtService.decode(sso_token)
    phone = claims&.dig(:phone).to_s.strip
    return nil if phone.blank?

    lock_key = "persistent_signin_otp:#{shop.id}:#{device_id}"
    # Raw SET NX so it works on Sidekiq 7's redis-client adapter. Guards two cart syncs racing.
    locked = Sidekiq.redis { |r| r.call('SET', lock_key, '1', 'NX', 'EX', PERSISTENT_SIGNIN_LOCK_TTL.to_s) }
    return where(device_id: device_id).first unless locked

    where(device_id: device_id).first || create!(
      shop: shop,
      device_id: device_id,
      phone: phone,
      country_code: claims[:country_code].presence || country_from_phone(phone),
      ver_type: PERSISTENT_SIGNIN,
      status: nil,
      is_charged: true,
      actual_charge_applied: 0,
      verification_status: 'OTP-Verified',
      notes: 'Persistent sign-in session (no OTP sent)',
      cart_details: cart_details,
      order_status: 'IN_PROGRESS'
    )
  rescue StandardError => e
    Rails.logger.error("[persistent_signin_otp] shop=#{shop&.id} device=#{device_id} #{e.class}: #{e.message}")
    nil
  end

  def self.country_from_phone(phone)
    Phonelib.parse(phone.start_with?('+') ? phone : "+#{phone}").country
  rescue StandardError
    nil
  end

  private

  def update_wallet_balance
    ver_type_for_wallet = ver_type == 'WHATSAPP' ? 'WHATSAPP' : 'SMS'
    NetworkServices::FreeWalletService.new(shop, self.country_code, ver_type_for_wallet).call
  end

end
