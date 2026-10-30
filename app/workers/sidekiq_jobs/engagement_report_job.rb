module SidekiqJobs
  class EngagementReportJob
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform
      # Send report for yesterday's engagement
      date = Date.yesterday
      EngagementMailer.daily_engagement_report(date).deliver_now
      
      Rails.logger.info "Engagement report sent for #{date}"
    rescue => e
      Rails.logger.error "Error sending engagement report: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end
end

