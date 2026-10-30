# frozen_string_literal: true

class ShopReportMailer < ApplicationMailer
  default from: "info@notifiktech.com"

  BRAND_LOGO_URL =
    "https://cdn.shopify.com/s/files/1/0655/2089/4070/files/with_bg_logo2.png?v=1770038556".freeze

  # recipients: String or Array of emails
  # manage_reports_url: optional; link for merchants to open Reports in admin and turn scheduling off.
  def scheduled_report(
    recipients,
    subject,
    body_text,
    body_html,
    attachment_name,
    attachment_content,
    manage_reports_url: nil
  )
    to = recipients.is_a?(Array) ? recipients.join(",") : recipients.to_s
    if attachment_name.present? && attachment_content.present?
      attachments[attachment_name] = {
        mime_type: "text/csv; charset=UTF-8",
        content: attachment_content,
      }
    end

    @mail_subject = subject.to_s.dup.force_encoding("UTF-8").scrub
    @body_text_plain = body_text.to_s.dup.force_encoding("UTF-8").scrub
    @report_body_html =
      body_html.to_s.dup.force_encoding("UTF-8").scrub.html_safe
    @email_heading =
      @mail_subject.sub(/\A\[TEST\]\s*/i, "").strip.presence || "Scheduled report"
    @has_csv_attachment = attachment_name.present? && attachment_content.present?
    @manage_reports_url =
      manage_reports_url.presence&.dup&.force_encoding("UTF-8")&.scrub
    @brand_logo_url = BRAND_LOGO_URL.dup.force_encoding("UTF-8").scrub

    mail(to: to, subject: subject) do |format|
      format.text { render "scheduled_report", layout: false }
      format.html { render "scheduled_report", layout: false }
    end
  end
end
