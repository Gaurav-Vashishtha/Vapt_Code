# frozen_string_literal: true

module SupportDashboard
  # Support tool: watch what a merchant actually did during onboarding.
  #
  # #index lists the recordings still inside the retention window with the
  # furthest onboarding stage each one reached, so the drop-offs can be read off
  # the list before opening anything. #show plays one back (rrweb-player) with
  # the shop's funnel events as seekable markers on the timeline. #events serves
  # the inflated rrweb stream as JSON — kept out of the HTML so a 30-minute
  # session doesn't produce a multi-megabyte page.
  class SessionRecordingsController < ApplicationController
    before_action :authenticate_admin!

    PER_PAGE = 50

    def index
      @retention_hours = SessionRecordingPolicy.retention_hours
      @sample_percent  = SessionRecordingPolicy.sample_percent
      @recording_enabled = SessionRecordingPolicy.enabled?

      @domain = normalize_shop_domain(params[:shop_domain])
      @only_drops = params[:only_drops].to_s == "1"
      @min_seconds = params[:min_seconds].presence&.to_i || 5
      @page = [params[:page].to_i, 1].max

      scope = SessionRecording.watchable
      scope = scope.for_domain(@domain) if @domain.present?
      scope = scope.where("duration_ms >= ?", @min_seconds * 1000) if @min_seconds.positive?

      @total = scope.count
      recordings = scope.recent.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a

      stages = stages_for(recordings)
      recordings.reject! { |r| stages[r.id][:converted] } if @only_drops

      @rows = recordings.map { |r| { recording: r }.merge(stages[r.id]) }
      @stage_summary = summarize(stages.values)
      @storage_mb = (SessionRecording.sum(:compressed_bytes).to_f / 1.megabyte).round(1)
    end

    def show
      @recording = SessionRecording.find(params[:id])
      @onboarding_events = @recording.onboarding_events.to_a
      @last_stage = @recording.last_stage(@onboarding_events)
      @converted = @onboarding_events.any? { |e| e.event == "billing_approved" }

      # Player markers are offsets from the first rrweb event, which is what
      # rrweb-player's goto() takes.
      origin = @recording.started_at
      @markers = @onboarding_events.map do |event|
        {
          label: stage_label(event.event),
          event: event.event,
          step: event.step,
          at: event.occurred_at,
          offset_ms: ((event.occurred_at - origin) * 1000).to_i.clamp(0, @recording.duration_ms.to_i),
          # Absolute time: the player re-bases markers on the first event it
          # actually plays, which can differ from started_at when leading
          # events had to be trimmed.
          at_ms: (event.occurred_at.to_f * 1000).to_i
        }
      end
    end

    def events
      recording = SessionRecording.find(params[:id])
      render json: { events: recording.all_events }
    end

    private

    # One query for every domain on the page, then matched to each recording's
    # own window in Ruby — a per-recording query would be N+1 across 50 rows.
    def stages_for(recordings)
      domains = recordings.map(&:shopify_domain).uniq
      return {} if domains.empty?

      window_start = recordings.map(&:started_at).min
      window_end   = recordings.map(&:last_event_at).max + 2.minutes

      by_domain = OnboardingEvent
                    .where(shopify_domain: domains, occurred_at: window_start..window_end)
                    .order(:occurred_at)
                    .to_a
                    .group_by(&:shopify_domain)

      recordings.index_with do |recording|
        own = (by_domain[recording.shopify_domain] || []).select do |event|
          event.occurred_at.between?(recording.started_at, recording.last_event_at + 2.minutes)
        end

        stage = recording.last_stage(own)
        {
          stage: stage,
          stage_label: stage ? stage[:label] : "No funnel event",
          converted: own.any? { |e| e.event == "billing_approved" },
          event_count: own.size
        }
      end.transform_keys(&:id)
    end

    # { stage label => how many of these sessions stopped there } — the drop-off
    # table at the top of the page.
    def summarize(rows)
      counts = Hash.new(0)
      rows.each { |row| counts[row[:stage_label]] += 1 }
      counts.sort_by { |_label, count| -count }
    end

    def stage_label(event_key)
      stage = OnboardingEvent::FUNNEL_STAGES.find { |s| OnboardingEvent.events_for(s).include?(event_key) }
      stage ? stage[:label] : event_key.to_s.humanize
    end

    def authenticate_admin!
      http_basic_authenticate_or_request_with(
        name: ENV.fetch("ADMIN_USER", nil),
        password: ENV.fetch("ADMIN_PASS", nil),
      )
    end

    def normalize_shop_domain(raw)
      s = raw.to_s.strip.downcase.delete_suffix("/")
      return "" if s.blank?

      s.include?(".") ? s : "#{s}.myshopify.com"
    end
  end
end
