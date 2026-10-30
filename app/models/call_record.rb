# frozen_string_literal: true

class CallRecord < ApplicationRecord
  OUTCOMES = %w[
    onboarded reonboarded demo_scheduled not_interested not_connected whatsapp_dropped
    callback_requested voicemail wrong_number do_not_call busy language_barrier
  ].freeze

  OUTCOME_LABELS = {
    "onboarded" => "Onboarded",
    "reonboarded" => "Reonboarded",
    "demo_scheduled" => "Demo scheduled",
    "not_interested" => "Not interested",
    "not_connected" => "Call not connected",
    "whatsapp_dropped" => "Dropped WhatsApp message",
    "callback_requested" => "Callback requested",
    "voicemail" => "Voicemail / no answer",
    "wrong_number" => "Wrong / invalid number",
    "do_not_call" => "Do not call",
    "busy" => "Busy — call later",
    "language_barrier" => "Language barrier"
  }.freeze

  SUCCESS_OUTCOMES = %w[onboarded reonboarded].freeze
  SHORT_RETRY_OUTCOMES = %w[not_connected voicemail busy].freeze
  SUPPRESS_OUTCOMES = {
    "not_interested" => { reason: "not_interested", days: 90 },
    "wrong_number" => { reason: "invalid_number", days: nil },
    "do_not_call" => { reason: "do_not_call", days: nil }
  }.freeze

  scope :on_date, ->(date) { where(called_at: date.beginning_of_day..date.end_of_day) }
  scope :for_domain, ->(domain) { where(shopify_domain: domain) }

  def self.last_called_at_by_domain
    group(:shopify_domain).maximum(:called_at)
  end

  def outcome_label
    OUTCOME_LABELS.fetch(outcome, outcome)
  end
end
