# frozen_string_literal: true

# One rrweb recording of a merchant's session in the embedded app, captured
# only during the post-install window (see SessionRecordingPolicy) and kept for
# SESSION_RECORDING_RETENTION_HOURS.
#
# Events live in session_recording_chunks as gzipped JSON; this row is the
# index the support dashboard lists and filters on.
class SessionRecording < ApplicationRecord
  # optional: the shop row is destroyed on uninstall and the recording has to
  # outlive it — shopify_domain is the durable identifier.
  belongs_to :shop, optional: true
  has_many :chunks, -> { order(:seq) },
           class_name: "SessionRecordingChunk", dependent: :delete_all

  validates :shopify_domain, :session_key, presence: true

  scope :recent, -> { order(started_at: :desc) }
  scope :since,  ->(time) { where(started_at: time..) }
  scope :for_domain, ->(domain) { where(shopify_domain: domain.to_s.strip.downcase) }
  # Anything shorter is a bounce/refresh with nothing to watch.
  scope :watchable, -> { where("event_count >= ?", 2) }

  # Onboarding funnel events the same shop emitted while this recording was
  # live. These are what turn "a video" into "where they dropped": the player
  # page lists them as seekable markers on the timeline.
  #
  # A small tail is included because the wizard's last event (e.g.
  # billing_approved) often lands just after the tab is closed.
  def onboarding_events(tail: 2.minutes)
    return OnboardingEvent.none if shopify_domain.blank?

    OnboardingEvent
      .where(shopify_domain: shopify_domain)
      .where(occurred_at: started_at..(last_event_at + tail))
      .order(:occurred_at)
  end

  # Furthest funnel stage reached during (or just after) this session, as a
  # FUNNEL_STAGES entry. nil when the merchant emitted nothing at all.
  def last_stage(events = nil)
    seen = (events || onboarding_events).map(&:event).uniq
    OnboardingEvent::FUNNEL_STAGES.reverse.find do |stage|
      (OnboardingEvent.events_for(stage) & seen).any?
    end
  end

  def converted?
    onboarding_events.where(event: "billing_approved").exists?
  end

  def duration_label
    secs = (duration_ms.to_i / 1000.0).round
    secs < 60 ? "#{secs}s" : "#{secs / 60}m #{format('%02d', secs % 60)}s"
  end

  # Every event of the recording, inflated and merged in timestamp order.
  # Chunks arrive in sequence but a retry can land out of order, so sort.
  def all_events
    chunks.flat_map { |chunk| chunk.events }.sort_by { |event| event["timestamp"].to_i }
  end
end
