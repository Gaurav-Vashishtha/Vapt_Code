# frozen_string_literal: true

module SupportCalls
  class MorningQueueEmailJob < ApplicationJob
    sidekiq_options queue: "administration", retry: 1

    def perform
      date = Date.current
      return if date.sunday?

      SupportCalls::QueueBuilder.new(date: date).build!
      CallCalendarMailer.morning_queue(date.to_s).deliver_now
    rescue => e
      Rails.logger.error("[SupportCalls::MorningQueueEmailJob] #{e.class}: #{e.message}")
    end
  end
end
