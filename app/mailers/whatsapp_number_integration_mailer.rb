# app/mailers/whatsapp_number_integration_mailer.rb
class WhatsappNumberIntegrationMailer < ApplicationMailer
  def notify_approvers(integration_request_id)
    @integration_request = WhatsappNumberIntegrationRequest.find(integration_request_id)
    
    # Get approver emails from settings or environment
    approver_emails = ENV['WHATSAPP_APPROVERS_EMAIL_LIST']&.split(',')
    
    mail(
      to: approver_emails,
      subject: "New WhatsApp Number Integration Request from #{@integration_request.shop_domain}",
      template_path: 'whatsapp_number_integration_mailer',
      template_name: 'notify_approvers'
    )
  end
  
  def send_acknowledgment(integration_request_id)
    @integration_request = WhatsappNumberIntegrationRequest.find(integration_request_id)
    
    mail(
      to: @integration_request.email,
      subject: 'Your WhatsApp Number Integration Request Has Been Received - Cod King',
      template_path: 'whatsapp_number_integration_mailer',
      template_name: 'acknowledgment'
    )
  end
end

