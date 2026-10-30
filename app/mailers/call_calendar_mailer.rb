# frozen_string_literal: true

class CallCalendarMailer < ApplicationMailer
  def morning_queue(date_str)
    @date = Date.parse(date_str)
    @targets = CallTarget.for_date(@date).ranked
    @day_owner = @targets.first&.assigned_engineer || SupportCalls::DayOwner.for_date(@date)
    @due_domains = CallReminder.open_domains_due_by(@date).to_set

    mail(to: recipients, subject: "Call queue — #{@date.strftime('%d %b %Y')} (#{@targets.size} calls)")
  end

  def evening_report(date_str)
    @date = Date.parse(date_str)
    @report = SupportCalls::DailyReport.new(@date).to_h

    mail(to: recipients, subject: "Call report — #{@date.strftime('%d %b %Y')} (#{@report[:attempted]}/#{@report[:target]} attempted)")
  end

  private

  def recipients
    ENV["WHATSAPP_APPROVERS_EMAIL_LIST"].presence || "support@notifiktech.com"
  end
end
