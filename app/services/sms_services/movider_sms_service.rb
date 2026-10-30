module SmsServices
  class MoviderSmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params


    # @shop = Shop.last
    # @order_confirmation = OrderConfirmation.last
    # resp = @shop.setting.provider.constantize.call(
    #   @shop.setting.provider_api_key,
    #   @shop.setting.provider_sender_id,
    #   {
    #     to: @order_confirmation.customer_number,
    #     body: 'hello',
    #     dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
    #   }
    # )

    def initialize(api_key, sender_id, params)
      @api_key = api_key.split(':')
      @sender_id = sender_id
      @params = params
    end

    def call
      begin
        uri = URI.parse("https://api.movider.co/v1/sms")
        request = Net::HTTP::Post.new(uri)

        body = @params[:body]
        if @sender_id==ENV['MOVIDER_SENDER_ID']
           body =  "#{@params[:body]} - #{@sender_id}"
        end
        if @sender_id==ENV['MOVIDER_SENDER_ID_OTP'] #Have a separate OTP sender ID.
          # Extract verification code (number at the beginning) and transform the message
          if @params[:body] =~ /^(\d+)\s+is your verification code/
            verification_code = $1
            body = "#{verification_code} is your verification code to proceed with order - #{@sender_id}"
          else
            body = @params[:body]
          end
        end

        request.body = "to=#{params[:to]}&text=#{body}&api_key=#{@api_key.first}&api_secret=#{@api_key.last}&from=#{@sender_id}"
        req_options = {
          use_ssl: uri.scheme == "https",
        }

        response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
          http.request(request)
        end
        parsed_response = JSON.parse(response.body)
        puts "parsed response #{parsed_response}"
        if !parsed_response['total_sms'].blank? && parsed_response['total_sms'].to_i>0
          return OpenStruct.new({
            sid: 'movider:' + parsed_response['phone_number_list'].first['message_id']
          })
        else
          return OpenStruct.new({
            sid: nil,
            error: parsed_response
          })  
        end
      rescue Error => e
        return OpenStruct.new({
          sid: nil,
          error: e.message + parsed_response
        })
      end
    end
  end
end