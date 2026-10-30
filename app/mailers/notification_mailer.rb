class NotificationMailer < ApplicationMailer
    layout 'mailer'
  
    def send_dynamic_notification(shop, template_name, variables)
      @shop = shop
      variables.each { |key, val| instance_variable_set("@#{key}", val) }
  
      mail(
        to: shop.owner_email,
        subject: NotificationTemplate.find_by(name: template_name)&.subject || "Notification"
      ) do |format|
        format.html { render "notification_mailer/#{template_name}" }
      end
    end
  end
  