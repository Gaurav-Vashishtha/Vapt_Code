# frozen_string_literal: true

module AdminJobs
  class ParcelxCreditAlertJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 1

    DEFAULT_THRESHOLD = 20_000

    def perform
      credits = NetworkServices::ParcelxCreditService.call
      if credits.nil?
        Rails.logger.warn('[ParcelxCreditAlertJob] could not read remaining credits, skipping')
        return
      end

      threshold = self.class.threshold
      Rails.logger.info("[ParcelxCreditAlertJob] remaining=#{credits} threshold=#{threshold}")
      return if credits >= threshold

      ParcelxMailer.low_credits(credits, threshold).deliver_now
    rescue => e
      Rails.logger.error("[ParcelxCreditAlertJob] #{e.class}: #{e.message}")
    end

    def self.threshold
      Integer(ENV['PARCELX_CREDIT_ALERT_THRESHOLD'].to_s.strip, exception: false) || DEFAULT_THRESHOLD
    end
  end
end
