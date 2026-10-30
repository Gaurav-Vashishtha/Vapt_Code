module OrderConfirmationServices
  class OrderConfirmationPostService < ApplicationService
    include TwilioHelper
    attr_reader :shop, :client

    COD_TAGS = %w[cash cod bogus manual]

    def initialize(shop, order)
      @shop = shop
      @order = order
    end

    def call
      params = JSON.parse(@order.to_json).to_h
      create_order(params)
    end

    def create_order(params)
      existing_order = OrderConfirmation.find_by(order_id: params['id'])
      if params['shipping_address']['phone'].blank?
        ShopifyServices::OrderTagsAddService.call(
          @shop, params['id'], '❌ COD-MOBILE-NUMBER-MISSING'
        )
      end
      if !existing_order && (params['source_name'] != 'pos')
        if @shop.setting.sms || @shop.setting.ivr
          puts "OrderID #{params['id']} contains COD for #{params['payment_gateway_names']}"
          @order_confirmation = OrderConfirmation.new(
            payload_to_order_confirmation(params)
          )
          if @order_confirmation.save
            ShopifyJobs::OrderPostJob.perform_async(@shop.id, @order_confirmation.id)
            @order_confirmation
          else
            puts "OrderConfirmation errors #{@order_confirmation.errors}"
            SlackNotifyJob.perform_async(
              ":rage:  (#{Rails.env})\n  *Error* orders/create webhook \n Input: #{payload_to_order_confirmation(params)}  \n Messages: #{@order_confirmation.errors.messages}"
            )
            @order_confirmation.errors
          end
        else
          puts "OrderID #{params['id']} does not contains COD or COD app is not enabled."
          { json: { success: true } }
        end
      elsif @shop.setting.sms || @shop.setting.ivr
        existing_order
      else
        puts "OrderID #{params['id']} does not contains COD or COD app is not enabled."
        { json: { success: true } }
      end
    end

    def payload_to_order_confirmation(params)
      begin
        phone_number = clean_phone_number(
          params.dig('shipping_address', 'phone'),
          params.dig('shipping_address', 'country_code').downcase
        )
      rescue Exception => e
        phone_number = ''
        SlackNotifyJob.perform_async(
          "Phone number not found in shipping_address #{params}"
        )
      end
      {
        order_id: params['id'],
        order_amount: params['total_price'],
        customer_name: params.dig('customer', 'first_name') + ' ' + params.dig('customer', 'last_name'),
        # customer_number: params['customer']['phone'], #to check if this is right phone number...
        # this needs improvements gsub wont be suffiecient
        # user may or may not enter country code
        customer_number: phone_number,
        shop_id: @shop.id,
        status: is_cod(params) ? 'Pending' : 'Non-COD',
        country_code: order_confirmation.get_country_code(params),
        ver_type: get_ver_type,
        is_charged: false,
        order_number: params['order_number'],
        order_status_url: params['order_status_url'],
        customer_locale: params['customer_locale'],
        customer_id: params.dig('customer', 'id'),
        customer_email: params.dig('customer', 'email'),
        currency: params['currency'],
        shipping_address: params['shipping_address'],
        persisted_otp: OrderConfirmation.derived_otp(@shop.id, params['id'])
      }
    end

    def clean_phone_number(phone, country_code)
      Phonelib.parse(phone, country_code).to_s
    rescue Exception => e
      SlackNotifyJob.perform_async(
        ":rage:  (#{Rails.env})\n *Error* Phonelib parse \n Phone: #{phone}  \n country_code: #{country_code} \n error: #{e.message}"
      )
      phone
    end

    def is_cod(params)
      payment_gateways = params['payment_gateway_names'].map(&:downcase)
      payment_gateways.each do |payment_gateway|
        COD_TAGS.each do |cod_tag|
          return true if payment_gateway.include? cod_tag
        end
      end
      if params['gateway']
        COD_TAGS.each do |cod_tag|
          return true if params['gateway'].downcase.include? cod_tag
        end
      end
      return true if params['gateway'].blank? && params['payment_gateway_names'].blank?

      false
    end

    def get_ver_type
      if @shop.setting.sms
        'SMS'
      else
        'IVR'
      end
    end
  end
end
