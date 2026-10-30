module NetworkJobs
  class SendSmsJob < ApplicationJob
    def perform(_shop_id, order_confirmation_id, template = '', dlt_id = '')
      shop=Shop.find(_shop_id)

      if shop.shopify_domain == 'sh97fb-0q.myshopify.com' 
        order_confirmation = OrderConfirmation.find(order_confirmation_id)
        
        # Clean the customer number
        customer_number = order_confirmation.customer_number
        sanitized_number = customer_number.gsub(/[+\s]/, '')
      
        # Check if it starts with 63 or 09
        return unless sanitized_number.start_with?("63", "09")
      
        # your remaining logic for valid numbers
      end

      if shop.setting.post_send_only_whatsapp
        order_confirmation = OrderConfirmation.find(order_confirmation_id)
        NetworkServices::WhatsappService.call(shop,order_confirmation)
        return
      end
      NetworkServices::SendSmsService.call(order_confirmation_id, template, dlt_id, false)
    end
  end
end
