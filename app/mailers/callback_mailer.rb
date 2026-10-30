# app/mailers/callback_mailer.rb
class CallbackMailer < ApplicationMailer
    def notify_approvers(callback_request_id)
      @callback_request = CallbackRequest.find(callback_request_id)
      
      # Get approver emails from settings or environment
      approver_emails = ENV['WHATSAPP_APPROVERS_EMAIL_LIST']&.split(',')
      
      mail(
        to: approver_emails,
        subject: "New Callback Request from #{@callback_request.shop_domain}",
        template_path: 'callback_mailer',
        template_name: 'notify_approvers'
      )
    end
    
    def send_acknowledgment(callback_request_id)
      @callback_request = CallbackRequest.find(callback_request_id)
      
      mail(
        to: @callback_request.email,
        subject: 'Your Callback Request Has Been Received - Cod King',
        template_path: 'callback_mailer',
        template_name: 'acknowledgment'
      )
    end
  end