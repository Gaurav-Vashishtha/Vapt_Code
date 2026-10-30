# frozen_string_literal: true

module MetaEvents
  # Builds and ships one batch from the web pixel to the Conversions API.
  # Called inline from MetaEventsController — there is no background queue on this path.
  class Dispatcher
    def initialize(shop:, events:, client_ip:, client_user_agent:)
      @shop = shop
      @events = events
      @client_ip = client_ip
      @client_user_agent = client_user_agent
    end

    def call
      setting = @shop.setting
      return unless setting&.meta_events_active?

      built = ::MetaEvents::EventBuilder.build_all(
        @events,
        client_ip: @client_ip,
        client_user_agent: @client_user_agent,
      )
      return if built.empty?

      result = ::MetaEvents::CapiClient.new(setting).send_events(built)
      log(built, result)
      requeue(result)
      result
    end

    private

    # The only place this path touches Sidekiq. Enqueuing must never take the request
    # down with it — a dropped event beats a 500 on the storefront.
    def requeue(result)
      return if result.retryable.blank?

      ::MetaEvents::RetryJob.perform_in(30.seconds, @shop.id, result.retryable.as_json)
      Rails.logger.info(
        "[MetaEvents] queued #{result.retryable.size} event(s) for retry " \
        "shop=#{@shop.shopify_domain}",
      )
    rescue StandardError => e
      Rails.logger.warn("[MetaEvents] retry enqueue failed: #{e.class}: #{e.message}")
    end

    def log(built, result)
      names = built.map { |event| event[:event_name] }.tally

      if result.errors.any?
        Rails.logger.warn(
          "[MetaEvents] shop=#{@shop.shopify_domain} sent=#{result.sent} " \
          "received=#{result.received} events=#{names.to_json} errors=#{result.errors.inspect}",
        )
      else
        Rails.logger.info(
          "[MetaEvents] shop=#{@shop.shopify_domain} sent=#{result.sent} " \
          "received=#{result.received} events=#{names.to_json}",
        )
      end
    end
  end
end
