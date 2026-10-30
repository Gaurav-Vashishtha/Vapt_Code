class EngagementMailer < ApplicationMailer
  def daily_engagement_report(date = Date.yesterday)
    @date = date
    @date_range = date.beginning_of_day..date.end_of_day
    @engagement_data = EngagementTrackingService.calculate_engagement(@date_range)
    @summary = EngagementTrackingService.total_engagement_summary(@date_range)
    
    # Get recipient emails from WHATSAPP_APPROVERS_EMAIL_LIST
    recipients = ENV['WHATSAPP_APPROVERS_EMAIL_LIST'] || 'support@notifiktech.com'
    
    mail(
      to: recipients,
      subject: "Daily Engagement Report - #{date.strftime('%B %d, %Y')}"
    )
  end
end

