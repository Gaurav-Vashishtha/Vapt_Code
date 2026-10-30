# frozen_string_literal: true

module CodForm
  module Tracking
    # CodForm::Tracking::ServerDispatchJob.perform_async(session_id, moment)   (K.9)
    #   moment: "initiate_checkout" | "purchase"
    #
    # First run: every matching pixel, each isolated. A pixel that fails for a reason a later
    # attempt can fix (network, 429, 5xx) is re-enqueued ALONE (`only`), up to MAX_ATTEMPTS, so
    # a retry never re-sends to the vendors that already answered. All events carry the shared
    # event id, so a duplicate delivery is deduplicated by the vendor anyway.
    # Never logs PII or tokens; errors are warn lines plus one Slack alert per shop per hour
    # once failures pass ALERT_THRESHOLD (NFR-7: error-only).
    class ServerDispatchJob < ApplicationJob
      sidekiq_options queue: "default", retry: 3

      MAX_ATTEMPTS = 3
      BACKOFF_SECONDS = [30, 300, 1800].freeze
      ALERT_THRESHOLD = 5
      DONE_TTL = 15.minutes

      def self.find_session(session_id)
        if session_id.to_s.match?(/\A\d+\z/)
          CodForm::Session.find_by(id: session_id)
        else
          CodForm::Session.find_by(public_id: session_id.to_s)
        end
      end

      def perform(session_id, moment, only = nil, attempt = 0)
        return unless EventMap.moment?(moment)

        session = self.class.find_session(session_id)
        return if session.nil? || session.is_test

        done_key = "codf:sd:#{session.id}:#{moment}"
        return if only.nil? && CodForm::Cache.store.exist?(done_key)

        results = Dispatcher.call(session: session, moment: moment, only: only)
        results.each { |result| handle(session, moment, result, attempt.to_i) }
        CodForm::Cache.store.write(done_key, 1, expires_in: DONE_TTL) if only.nil?
      end

      private

      def handle(session, moment, result, attempt)
        return if result["ok"]

        Rails.logger.warn(
          "[codf/pixels] shop=#{session.shop_id} session=#{session.id} moment=#{moment} " \
          "platform=#{result['platform']} status=#{result['status'].inspect} error=#{result['error']} attempt=#{attempt}"
        )
        if result["retryable"] && attempt < MAX_ATTEMPTS
          self.class.perform_in(BACKOFF_SECONDS[attempt] || BACKOFF_SECONDS.last, session.id, moment.to_s,
                                result["key"], attempt + 1)
        else
          count_failure(session.shop_id, result["platform"])
        end
      end

      def count_failure(shop_id, platform)
        key = "codf:sd:fail:#{shop_id}:#{Time.current.utc.strftime('%Y%m%d%H')}"
        count = CodForm::Cache.store.increment(key, 1, expires_in: 2.hours)
        if count.nil?
          CodForm::Cache.store.write(key, 1, expires_in: 2.hours)
          count = 1
        end
        return unless count == ALERT_THRESHOLD + 1

        SlackNotifyJob.perform_async(
          ":warning: COD Form server pixels: more than #{ALERT_THRESHOLD} failed events this hour " \
          "for shop #{shop_id} (last platform: #{platform}) (#{Rails.env})"
        )
      rescue StandardError => e
        Rails.logger.warn("[codf/pixels] failure counter error: #{e.class}")
      end
    end
  end
end
