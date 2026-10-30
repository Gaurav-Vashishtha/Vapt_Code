module NetworkServices
  class SendPrepaidMessageService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation

    #NetworkServices::SendPrepaidMessageService.call(Shop.last,OrderConfirmation.last)

    def initialize(shop, order_confirmation, reminder: nil, send_key: nil)
      @shop = shop
      @order_confirmation = order_confirmation
      @reminder = reminder # resolved per-reminder overrides (or nil for legacy path)
      @send_key = send_key
    end

    def call
      resp = ''
      if !@order_confirmation.blank? && @shop.setting.prepaid_notif
        # Paused means silence: no payment link, and no fallback to the shared number.
        return :paused if NetworkServices::WhatsappPrepaidBspService.paused?(@shop)


        if @shop.setting.payment_provider=='PHONEPE'
          if @order_confirmation.digest.blank?
            NetworkServices::PhonepeLinkService.call(@shop,@order_confirmation)
          end
          prepaid_link =  NetworkServices::CutlyLinkService.call("https://#{ENV['APP_HOST']}/order_confirmations/redirect_to_prepaid_link/?digest=#{@order_confirmation.digest}")
          @order_confirmation.update(prepaid_link:prepaid_link)
        elsif @shop.setting.payment_provider=='PAYMOB'
          NetworkServices::PaymobLinkService.call(@shop,@order_confirmation)
        elsif @shop.setting.payment_provider=='GE_IDEA'
          NetworkServices::GeideaLinkService.call(@shop,@order_confirmation)
        elsif @shop.setting.payment_provider=='PAYU'
          NetworkServices::PayuLinkService.call(@shop, @order_confirmation, reminder: @reminder)
        elsif @shop.setting.payment_provider=='CASHFREE'
          NetworkServices::CashfreeLinkService.call(@shop, @order_confirmation, reminder: @reminder)
        else
          # Pass the reminder so RazorpayLinkService regenerates the link with
          # the reminder's discount (instead of reusing an earlier link bound
          # to the shop default discount).
          NetworkServices::RazorpayLinkService.call(@shop, @order_confirmation, reminder: @reminder)
        end
        setting = @shop.setting
        if NetworkServices::WhatsappPrepaidBspService.eligible?(@shop, @reminder)
          resp = NetworkServices::WhatsappPrepaidBspService.call(
            @shop, @order_confirmation, reminder: @reminder, send_key: @send_key
          )

          # A #133010 mid-send marks the number unregistered, so the shop is no
          # longer BSP-eligible. Without this the reminder would be dropped
          # entirely: the branch below already ran past, and nothing retries.
          if resp.blank? && !NetworkServices::WhatsappPrepaidBspService.eligible?(@shop, @reminder)
            resp = send_without_bsp(setting)
          end
        else
          resp = send_without_bsp(setting)
        end
      end
    return resp;
    end

    private

    def send_without_bsp(setting)
      if @shop.shopify_domain =='zenithxx.myshopify.com'
        NetworkServices::WhatsappPrepaidZenithService.call(@shop,@order_confirmation)
      elsif setting.whatsapp_enabled && (ENV['WHATSAPP_COUNTRIES'].split(",").include? 'IN')
        NetworkServices::WhatsappPrepaidService.call(@shop,@order_confirmation, reminder: @reminder)
      else
        send_msg91_sms(setting)
      end
    end

    def send_msg91_sms(setting)
      sender_id = ENV['MSG_91_IN_SENDER']
      auth_key = ENV['MSG91_AUTHKEY']
      flow_id =  (setting.prepaid_discount==0) ? ENV['MSG91_PREPAID_ZERO_TEMPLATE_ID']: ENV['MSG91_PREPAID_REMINDER_TEMPLATE_ID']

      order_discount = (ShopifyServices::PrepaidOrderService.new(nil,order_confirmation.shop, order_confirmation.id).get_discount_amount(
        discount: (@reminder && @reminder['discount']),
        discount_type: (@reminder && @reminder['discount_type']),
        add_shipping: !!(@reminder && @reminder['add_shipping'])
      ))

      resp = SmsServices::Msg91PrepaidSmsService.call(
        { auth_key: auth_key },
        {
          flow_id: flow_id,
          sender: sender_id ,
          to: @order_confirmation.customer_number,
          discount: order_discount,
          payment_link: @order_confirmation.prepaid_link,
          store: @shop.setting.shop.owner_name
        }
      )
      TwilioLog.create(
        sid: resp.sid,
        ver_type: 'SMS',
        country_code: @order_confirmation.country_code,
        customer_number: @order_confirmation.customer_number,
        status: resp.sid ? 'SUCCESS' : resp.error,
        order_confirmation: @order_confirmation,
        shop: @shop
      )
      resp
    end
  end
end
