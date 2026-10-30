# frozen_string_literal: true

module SupportCalls
  class BuildDailyQueueJob < ApplicationJob
    sidekiq_options queue: "administration", retry: 1

    def perform(date_str = nil)
      date = date_str.present? ? Date.parse(date_str) : Date.current
      return if date.sunday?

      SupportCalls::QueueBuilder.new(date: date).build!
    rescue => e
      Rails.logger.error("[SupportCalls::BuildDailyQueueJob] #{e.class}: #{e.message}")
    end
  end
end
