require "json"
require "uri"
require "net/http"

module NetworkServices
    class CutlyLinkService < ApplicationService
      attr_reader :shop
      attr_reader :order_confirmation
  
      MAX_TRIES = 3
      #NetworkServices::CutlyLinkService.call('https://google.com')
  
      def initialize( long_url)
        @long_url = long_url
      end

      def call
          try = 0
          link ='false'
          while try < MAX_TRIES && link=='false'
            link = generate_cutly_link
            try = try+1
            puts "Try #{try}"
          end
        return link
      end

      def generate_cutly_link
  
      
        url = URI.parse("https://cutt.ly/api/api.php")
        params = {
          key: ENV.fetch("CUTLY_API_KEY", nil),
          short: @long_url,
          public: 1
        }
        url.query = URI.encode_www_form(params)
      
        begin
          resp = Net::HTTP.get_response(url)
          puts resp.body
          short_link = JSON.parse(resp.body)['url']['shortLink']
          puts short_link
          return short_link
        rescue Exception => e
          # SlackNotifyJob.perform_async(
          #   ":rage: (#{Rails.env})\n *Unable to create the shortlink #{@long_url} #{e}"
          # )
          puts e
          return "false"
        end
      end
  end
end