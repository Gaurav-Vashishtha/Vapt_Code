module SmsServices
  class ESmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key.split(':').first
      @api_secret = api_key.split(':').last
      @sender_id = sender_id
      @params = params
    end

    def call
      base_url = "http://rest.esms.vn/MainService.svc/json/SendMultipleMessage_V4_get"
      query_params = {
        Phone: @params[:to],
        Content: @params[:body],
        ApiKey: @api_key,
        SecretKey: @api_secret
      }
    
      if @sender_id.present?
        query_params[:SmsType] = 2
        query_params[:Brandname] = @sender_id
      else
        query_params[:SmsType] = 8
      end
    
      uri = URI(base_url)
      uri.query = URI.encode_www_form(query_params)
    
      begin
        resp = HTTParty.get(uri)
        puts "eSms response #{resp}"
        puts "eSms parsed_response #{resp.parsed_response}"
        if resp.ok?
          return OpenStruct.new({
            sid: 'eSms:' + resp.parsed_response['SMSID']
          })
        end
        return OpenStruct.new({
          sid: nil,
          error: "eSms: #{resp.parsed_response['SMSID']}"
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