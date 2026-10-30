module SmsServices
  class Msg91SmsAbandonedService < ApplicationService
    attr_reader :config
    attr_reader :params

    def initialize(config = {}, params = {})
      @config = config
      @params = params
    end

    def call
      url = "https://api.msg91.com/api/v5/flow/"
      begin
        uri = URI.parse(url)
      rescue URI::InvalidURIError
        uri = URI.parse(URI.escape(url))
      end
      begin
        resp = HTTParty.get(uri,
          body: {
            'flow_id': @params[:flow_id],
            'sender': @params[:sender],
            'mobiles': @params[:to].gsub('+', '').gsub(' ', ''),
            'store': @params[:store],
            'url': @params[:url],
            'name': @params[:name]
          },
          headers: {
            'Content-Type' => 'application/json',
            'authkey' => @config[:auth_key]
          },
          query_string_normalizer: ->(query) { query.to_json }
        )
        puts "Msg91 response #{resp}"
        puts "Msg91 parsed_response #{resp.parsed_response}"
        if resp.parsed_response['type'] == 'success'
          return OpenStruct.new({
            sid: resp.parsed_response['message']
          })
        end
        return OpenStruct.new({
          sid: nil,
          error: resp.parsed_response['message']
        })
      rescue Exception => e
        return OpenStruct.new({
          sid: nil,
          error: e.message
        })
      end
    end
  end
end