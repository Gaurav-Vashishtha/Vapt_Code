# frozen_string_literal: true

module MetaEvents
  # Off the hot path by design. MetaEventsController sends to the Conversions API
  # synchronously; this only picks up the events that failed for a transient reason
  # (Meta unreachable, 429, 5xx) so a Purchase isn't lost to a blip.
  #
  # The events handed over are already built and hashed by MetaEvents::EventBuilder, and
  # each carries its original event_id — Meta deduplicates a retry that arrives after the
  # original landed, so a double send is safe.
  class RetryJob < ApplicationJob
    sidekiq_options queue: "low", retry: 5

    class TransientFailure < StandardError; end

    def perform(shop_id, events)
      shop = Shop.find_by(id: shop_id)
      return if shop.blank?

      setting = shop.setting
      return unless setting&.meta_events_active?

      events = Array(events).map(&:deep_symbolize_keys)
      return if events.empty?

      # Meta rejects anything older than 7 days, so a retry that has been failing for
      # that long is dead weight rather than a recoverable event.
      events.reject! { |event| event[:event_time].to_i < 7.days.ago.to_i }
      return if events.empty?

      result = ::MetaEvents::CapiClient.new(setting).send_events(events)

      if result.retryable.any?
        Rails.logger.warn(
          "[MetaEvents] retry failed shop=#{shop.shopify_domain} events=#{events.size} " \
          "errors=#{result.errors.inspect}",
        )
        raise TransientFailure, "Meta CAPI still unreachable for #{shop.shopify_domain}"
      end

      Rails.logger.info(
        "[MetaEvents] retry ok shop=#{shop.shopify_domain} sent=#{result.sent} " \
        "received=#{result.received}",
      )
    end
  end
end
