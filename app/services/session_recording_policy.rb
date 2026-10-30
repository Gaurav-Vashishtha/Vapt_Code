# frozen_string_literal: true

# Decides whether a given shop's embedded-app session gets recorded.
#
# Three gates, all server-side so the browser never decides for itself:
#   1. kill switch        — SESSION_RECORDING_ENABLED=false turns everything off
#   2. post-install window — only the first SESSION_RECORDING_WINDOW_HOURS after
#      install, which is the onboarding wizard plus the merchant's first session
#   3. deterministic sampling — SESSION_RECORDING_SAMPLE_PERCENT of shops, hashed
#      on shop id so a sampled shop stays sampled for its whole window (a
#      per-request coin flip would produce half-recorded funnels)
#
# Retention is enforced separately by AdminJobs::PurgeSessionRecordingsJob.
class SessionRecordingPolicy
  DEFAULT_SAMPLE_PERCENT = 25
  DEFAULT_WINDOW_HOURS   = 48

  attr_reader :shop

  def initialize(shop)
    @shop = shop
  end

  def record?
    enabled? && shop.present? && within_window? && sampled?
  end

  def self.enabled?
    ENV.fetch("SESSION_RECORDING_ENABLED", "true").to_s.downcase != "false"
  end

  def self.sample_percent
    ENV.fetch("SESSION_RECORDING_SAMPLE_PERCENT", DEFAULT_SAMPLE_PERCENT).to_i.clamp(0, 100)
  end

  def self.window_hours
    ENV.fetch("SESSION_RECORDING_WINDOW_HOURS", DEFAULT_WINDOW_HOURS).to_i.clamp(0, 24 * 30)
  end

  def self.retention_hours
    ENV.fetch("SESSION_RECORDING_RETENTION_HOURS", 48).to_i
  end

  def enabled?
    self.class.enabled?
  end

  def within_window?
    installed_at = shop.created_at
    return false if installed_at.blank?

    installed_at >= self.class.window_hours.hours.ago
  end

  def sampled?
    pct = self.class.sample_percent
    return false if pct.zero?
    return true  if pct == 100

    bucket(shop.id) < pct
  end

  private

  # Stable 0..99 bucket. Salted so raising the percentage only ever adds shops
  # rather than reshuffling who is in the sample.
  def bucket(shop_id)
    Digest::MD5.hexdigest("session-recording:#{shop_id}").to_i(16) % 100
  end
end
