module SmsServices
    class BulkSmsBdService < ApplicationService
      attr_reader :api_key
      attr_reader :sender_id
      attr_reader :params
  
    #   Usage example:
    #   @shop = Shop.last
    #   @order_confirmation = OrderConfirmation.last
    #   resp = @shop.setting.provider.constantize.call(
    #     @shop.setting.provider_api_key,
    #     @shop.setting.provider_sender_id,
    #     {
    #       to: @order_confirmation.customer_number,
    #       body: 'hello',
    #       dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
    #     }
    #   )
  
      def initialize(api_key, sender_id, params)
        @api_key = api_key
        @sender_id = sender_id
        @params = params
      end
  
      def call
        begin
          # Build the request URL with query parameters
          base_url = "http://bulksmsbd.net/api/smsapi"
          query_params = {
            api_key: @api_key,
            type: 'text',
            number: @params[:to],
            senderid: @sender_id,
            message: @params[:body]
          }
          
          # Add DLT ID if provided
          query_params[:dlt_id] = @params[:dlt_id] if @params[:dlt_id].present?
          
          # Build URI with query string
          uri = URI.parse(base_url)
          uri.query = URI.encode_www_form(query_params)
          
          # Make the GET request
          req_options = {
            use_ssl: uri.scheme == "https",
            read_timeout: 30,
            open_timeout: 30
          }
  
          response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
            request = Net::HTTP::Get.new(uri)
            http.request(request)
          end
          
          puts "BulkSMSBD Response: #{response.body}"
          puts "BulkSMSBD Response Code: #{response.code}"
          
          # Parse response - BulkSMSBD typically returns JSON or simple text
          begin
            parsed_response = JSON.parse(response.body)
          rescue JSON::ParserError
            # If not JSON, treat as plain text response
            parsed_response = { "response" => response.body.strip }
          end
          
          puts "Parsed response: #{parsed_response}"
          
          # Check for successful response
          # BulkSMSBD typically returns success status in various formats
          # Adjust this logic based on actual API response format
          if response.code == "200" && is_success_response?(response.body, parsed_response)
            return OpenStruct.new({
              sid: generate_message_id(parsed_response),
              response: parsed_response
            })
          else
            return OpenStruct.new({
              sid: nil,
              error: parsed_response.is_a?(Hash) ? parsed_response : { "message" => response.body }
            })
          end
          
        rescue StandardError => e
          puts "BulkSMSBD Error: #{e.message}"
          return OpenStruct.new({
            sid: nil,
            error: { "message" => e.message, "response" => defined?(parsed_response) ? parsed_response : nil }
          })
        end
      end
  
      private
  
      def is_success_response?(response_body, parsed_response)
        # BulkSMSBD success indicators - adjust based on actual API responses
        return true if response_body.downcase.include?('success')
        return true if response_body.downcase.include?('sent')
        return true if parsed_response.is_a?(Hash) && parsed_response['status']&.downcase == 'success'
        return true if parsed_response.is_a?(Hash) && parsed_response['success'] == true
        
        # If response contains message ID or similar positive indicators
        return true if response_body.match?(/\d{10,}/) # Likely a message ID
        
        false
      end
  
      def generate_message_id(parsed_response)
        # Try to extract message ID from response
        if parsed_response.is_a?(Hash)
          message_id = parsed_response['message_id'] || 
                      parsed_response['id'] || 
                      parsed_response['sms_id'] ||
                      parsed_response['reference']
          
          return "bulksmsbd:#{message_id}" if message_id
        end
        
        # If no specific ID found, generate one with timestamp
        "bulksmsbd:#{Time.now.to_i}_#{@params[:to]}"
      end
    end
  end