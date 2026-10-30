class FormFunnelEvent < ApplicationRecord
  belongs_to :shop

  # Express funnel. The public, unauthenticated POST /form_funnel/ingest accepts exactly this
  # list, so it must NOT gain the COD Form types: several of those (cf_order_created, …) are
  # server-authoritative and would become forgeable through that endpoint.
  EVENT_TYPES = %w[form_view checkout_initiated].freeze

  # COD Form funnel (docs/cod-form/ARCHITECTURE.md I.1). The cf_ prefix keeps the two apart.
  # Written only through CodForm::FunnelLogger / CodForm::EventIngestService.
  # cf_button_view is counted in Redis and cf_client_error goes to Sentry: neither is stored
  # as a row; they are listed so the taxonomy is in one place.
  COD_FORM_EVENT_TYPES = %w[
    cf_button_view cf_form_open cf_first_input cf_shipping_selected cf_submit_attempt cf_submit_error
    cf_order_created cf_form_close cf_prepaid_redirect cf_partial_handoff cf_prepaid_order
    cf_otp_sent cf_otp_verified cf_otp_bypassed cf_offer_view cf_offer_accept cf_downsell_shown cf_downsell_accept
    cf_upsell_view cf_upsell_accept cf_recovery_open cf_blocked cf_fallback cf_client_error
  ].freeze

  ALL_EVENT_TYPES = (EVENT_TYPES + COD_FORM_EVENT_TYPES).freeze

  validates :event_type, presence: true, inclusion: { in: ALL_EVENT_TYPES }
  validates :session_token, presence: true

  scope :in_window, ->(from, to) { where(occurred_at: from..to) }
  scope :cod_form, -> { where(event_type: COD_FORM_EVENT_TYPES) }
end
