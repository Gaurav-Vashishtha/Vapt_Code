# frozen_string_literal: true

module SupportCalls
  class EveningReportEmailJob < ApplicationJob
    sidekiq_options queue: "administration", retry: 1

    def perform
      date = Date.current
      return if date.sunday?

      CallCalendarMailer.evening_report(date.to_s).deliver_now
    rescue => e
      Rails.logger.error("[SupportCalls::EveningReportEmailJob] #{e.class}: #{e.message}")
    end
  end
end
