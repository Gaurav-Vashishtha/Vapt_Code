# frozen_string_literal: true

class ScheduledEmailMailer < ApplicationMailer
  def rule_email(scheduled_email)
    @scheduled_email = scheduled_email
    @rule = scheduled_email.email_rule
    @template = @rule.email_template

    if scheduled_email.shop_id?
      @shop = scheduled_email.shop
      raw_body = EmailTemplateRendererService.render_body(@template, shop: @shop)
      subject = EmailTemplateRendererService.render_subject(@template, shop: @shop)
    else
      @uninstalled_shop = scheduled_email.uninstalled_shop
      raw_body = EmailTemplateRendererService.render_body(@template, uninstalled_shop: @uninstalled_shop)
      subject = EmailTemplateRendererService.render_subject(@template, uninstalled_shop: @uninstalled_shop)
    end

    base_url = "#{ActionMailer::Base.default_url_options[:protocol] || 'https'}://#{ActionMailer::Base.default_url_options[:host]}"
    @body = EmailTool::TrackingInjectService.call(scheduled_email, raw_body, base_url: base_url)

    to_email = scheduled_email.recipient_email.presence || "no-reply@example.com"
    mail(to: to_email, subject: subject) do |format|
      format.html { render html: @body.html_safe }
    end
  end
end
