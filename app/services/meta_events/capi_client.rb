# frozen_string_literal: true

module MetaEvents
  # POST {pixel_id}/events on the Graph API. Reuses Meta::GraphClient for the HTTParty
  # plumbing, error parsing and META_GRAPH_API_VERSION handling.
  #
  # This runs inline in the MetaEventsController request, so the timeout is not optional:
  # without it a stalled Graph API would pin a Puma thread until the socket gave up.
  class CapiClient
    BATCH_SIZE = 1000
    TIMEOUT_SECONDS = 3

    NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET,
      Errno::EHOSTUNREACH, SocketError, OpenSSL::SSL::SSLError, Timeout::Error
    ].freeze

    # +retryable+ holds the events from batches that failed for a reason a later attempt
    # could plausibly fix. A rejected payload or a bad token would fail identically on
    # every retry, so those are dropped rather than queued.
    Result = Struct.new(:sent, :received, :errors, :retryable, keyword_init: true)

    def initialize(setting)
      @setting = setting
    end

    def send_events(events)
      events = Array(events).compact
      return Result.new(sent: 0, received: 0, errors: [], retryable: []) if events.empty?

      client = ::Meta::GraphClient.new(
        token: @setting.pixel_token.to_s.strip,
        timeout: TIMEOUT_SECONDS,
      )
      received = 0
      errors = []
      retryable = []

      events.each_slice(BATCH_SIZE) do |batch|
        body = { data: batch }
        body[:test_event_code] = test_event_code if test_event_code.present?

        begin
          response = client.post("#{pixel_id}/events", body: body)
          received += response["events_received"].to_i
        rescue ::Meta::GraphClient::Error => e
          errors << e.message
          retryable.concat(batch) if transient_status?(e.status)
        rescue *NETWORK_ERRORS => e
          errors << "#{e.class}: #{e.message}"
          retryable.concat(batch)
        end
      end

      Result.new(sent: events.size, received: received, errors: errors, retryable: retryable)
    end

    private

    # 429 is Meta's rate limit, 5xx is Meta being unwell — both clear on their own.
    def transient_status?(status)
      status.to_i == 429 || status.to_i >= 500
    end

    def pixel_id
      @pixel_id ||= @setting.pixel_id.to_s.gsub(/\D/, "")
    end

    def test_event_code
      @test_event_code ||= @setting.pixel_test_event_id.to_s.strip
    end
  end
end
