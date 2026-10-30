module TwilioServices
  class CountryPriceService < TwilioServices::ApplicationService
    attr_reader :shop
    attr_reader :client

    def initialize(client, country_code)
      @client = client
      @country_code = country_code
    end

    def call
      begin
        country_prices = @client.pricing.v1.messaging.countries(@country_code).fetch
        max_price = country_prices.outbound_sms_prices
          .map { |carrier| carrier["prices"] }
          .flatten
          .map { |prices| prices["current_price"] }.max
        return max_price
        # puts "Country price.... #{max_price_carrier}"
      rescue Twilio::REST::RestError => e
        puts "Error getting country price: #{e.message}"
      end
    end
  end
end
