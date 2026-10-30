module NetworkServices
     # NetworkServices::ResendOtpService.call(OrderConfirmation.last.id)
  class ResendOtpService < ApplicationService
    
    MAX_TRIES = 2 #default max tries
    def initialize(order_confirmation_id)
      @order_confirmation_id = order_confirmation_id
    end

    def call
      @order_confirmation = OrderConfirmation.find_by(order_id: @order_confirmation_id)
      @shop = @order_confirmation.shop
      msg_count = @order_confirmation.twilio_logs.where(status:'SUCCESS').count

      if (msg_count< (@shop.setting.max_retries || MAX_TRIES))
        if ((ENV['WHATSAPP_COUNTRIES'].split(",").include? @order_confirmation.country_code) && (@shop.setting.whatsapp_enabled==true))
          NetworkServices::WhatsappRetryService.call(@shop,@order_confirmation)
        else  
          NetworkServices::SendSmsService.call(@order_confirmation.id, @shop.setting.retry_template, '',true)
        end
      else
        return nil
      end
    return @order_confirmation 
    end #call ends here
  end #class ends here
end#module ends here
