module TwilioServices
  class IvrCallService < TwilioServices::ApplicationService
    attr_reader :shop
    attr_reader :client

    def initialize(client, params)
      @client = client
      @params = params
    end

    def call
      begin
        resp = @client.calls.create(@params)
        # resp = @client.messages.create(@params.merge({
        #   to: "whatsapp:#{@params[:to]}"
        # }))
        puts "sent IVR.... #{resp}"
      rescue Twilio::REST::RestError => e
        SlackNotifier::CLIENT.ping(
          text: ":rage: Send IVR error (#{Rails.env})\n *Error* #{e.message}",
        )
        if e.message.include? 'phone number'
          return OpenStruct.new({
            sid: nil,
            error: I18n.t('admin.enter_valid_phone')
          })
        end
        return OpenStruct.new({
            sid: nil,
            error: I18n.t('admin.enable_region')
          })
      end
      return resp
    end
  end
end
