module SidekiqJobs
  class DeleteOldJob < ApplicationJob
    def perform(*args)
      Sidekiq::Monitor::Job.where('enqueued_at < ?', 2.days.ago).destroy_all
    end
  end
end