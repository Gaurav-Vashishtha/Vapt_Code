require 'net/http'
require 'json'
require 'uri'
require 'base64'

module SmsServices
  class SmsCountrySmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key  # Keep the direct API key
      @sender_id = sender_id
      @params = params
    end

    def call
      # Prepare the API endpoint
      url = URI.parse('https://restapi.smscountry.com/v0.1/Accounts/DwiKExOiICG3vfdv6JY3/SMSes/')
      # Construct the request body
      formatted_number = params[:number].gsub('+', '')
      body = {
        Text: params[:text],
        Number: formatted_number,
        SenderId: sender_id,
        Tool: 'API'
      }.to_json

      # Initialize a new HTTP request
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true  # Use SSL/TLS

      request = Net::HTTP::Post.new(url.path, {
        'Content-Type' => 'application/json',
        'Authorization' => "Basic #{api_key}"  # Include the API key for Basic Auth
      })

      request.body = body

      # Send the request and receive the response
      response = http.request(request)

      # Parse the JSON response
      response_body = JSON.parse(response.body)

      # Handle the response
      if response_body['MessageUUID']
        OpenStruct.new({
          sid: response_body['MessageUUID'],
          success: true 
        })
      else
        return   OpenStruct.new({
          error: response_body['Message'] || 'Unknown error',
          success: false 
        })
      end
    end
  end
end
