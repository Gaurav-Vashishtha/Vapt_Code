class OnboardingEvent < ApplicationRecord
  # shop_id is nulled (not the row deleted) when a shop uninstalls, so the event
  # outlives its shop — hence optional. The funnel relies on the denormalized
  # shopify_domain/country_code/shop_created_date captured below instead.
  belongs_to :shop, optional: true

  before_create :capture_shop_snapshot

  # Semantic funnel events emitted by the QuickOnboardingV2 wizard. Ordered list
  # also drives the support dashboard funnel (see SupportDashboardController#onboarding_funnel).
  #
  # A stage's count is the number of distinct shops that emitted ANY of its backing
  # events (see .events_for). `optional: true` marks side-steps that not every shop
  # passes through — the theme app embed only applies to OTP/partial-payment shops,
  # and the test notification is skippable. Step-over-step conversion is measured
  # against the previous REQUIRED stage so these optional steps don't show up as
  # bogus drop-offs (or impossible >100% "recoveries").
  FUNNEL_STAGES = [
    { key: "onboarding_started", label: "Started onboarding" },
    { key: "features_selected",  label: "Selected features" },
    { key: "theme_embed",        label: "Theme app embed",
      events: %w[theme_embed_detected theme_embed_skipped], optional: true },
    { key: "test_sent",          label: "Sent a test notification", optional: true },
    { key: "billing_started",          label: "Started billing" },
    { key: "subscription_page_viewed", label: "Viewed subscription page" },
    { key: "plan_selected",            label: "Selected a plan" },
    { key: "billing_approved",         label: "Approved billing" }
  ].freeze

  # Event keys backing a funnel stage (defaults to the stage key itself).
  def self.events_for(stage)
    stage[:events] || [stage[:key]]
  end

  # Non-funnel events we also record for context/debugging.
  OTHER_EVENTS = %w[reached_dashboard error].freeze

  # Feature toggles captured in the `features_selected` event metadata, in display
  # order. The wizard sends camelCase booleans, but Rails underscores the keys on
  # ingest, so the stored (and queried) keys are snake_case — e.g. the frontend's
  # `otpVerificationEnabled` lands as `otp_verification_enabled`.
  FEATURE_FLAGS = [
    { key: "otp_verification_enabled", label: "Phone Verification (OTP)" },
    { key: "partial_payment_enabled",  label: "Partial Payment" },
    { key: "sms_confirmation",         label: "SMS — order placed" },
    { key: "sms_fulfilment",           label: "SMS — fulfillment" },
    { key: "sms_abandoned",            label: "SMS — abandoned cart" },
    { key: "wa_confirmation",          label: "WhatsApp — order placed" },
    { key: "wa_fulfilment",            label: "WhatsApp — fulfillment" },
    { key: "wa_abandoned",             label: "WhatsApp — abandoned cart" },
    { key: "wa_cod_verification",      label: "WhatsApp — COD verification" }
  ].freeze

  validates :event, presence: true

  scope :since,  ->(time) { where("occurred_at >= ?", time) }
  scope :recent, -> { order(occurred_at: :desc) }

  private

  # Copy the shop attributes the funnel needs onto the event so they persist even
  # after the shop is uninstalled (and its Shop row destroyed).
  def capture_shop_snapshot
    return unless shop

    self.shopify_domain    ||= shop.shopify_domain
    self.country_code      ||= shop.country_code
    self.shop_created_date ||= shop.shop_created_date
  end
end
