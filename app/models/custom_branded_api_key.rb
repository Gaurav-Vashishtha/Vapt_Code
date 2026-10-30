# frozen_string_literal: true

# Bearer keys for the public custom-branded WhatsApp API (/api/v1/cb).
# One key belongs to one client; the key IS the tenant resolution — a
# shop_domain in a request body is only ever a cross-check. Raw tokens are
# never stored: we keep a SHA256 digest and show the token once at mint time.
class CustomBrandedApiKey < ApplicationRecord
  belongs_to :custom_branded_client

  TOKEN_PREFIX = 'cbk_'

  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  # Mints a key and returns [record, raw_token]. The raw token exists only in
  # this return value.
  def self.mint!(client:, label: nil)
    raw = "#{TOKEN_PREFIX}#{SecureRandom.hex(24)}"
    record = create!(custom_branded_client: client, label: label, token_digest: digest(raw))
    [record, raw]
  end

  # The digest index does the lookup; a miss and a revoked key are
  # indistinguishable to the caller.
  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    key = active.find_by(token_digest: digest(raw_token))
    key&.touch_last_used
    key
  end

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  def touch_last_used
    # Throttled: this runs on every API call, so avoid a write per request.
    return if last_used_at.present? && last_used_at > 5.minutes.ago

    update_column(:last_used_at, Time.current)
  rescue StandardError
    nil
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  def masked
    "#{TOKEN_PREFIX}…#{token_digest.last(6)}"
  end
end
