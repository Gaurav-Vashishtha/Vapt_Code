require 'net/http'
require 'json'
require 'uri'

#ShopifyServices::ShopifyAssetService.new(shop).is_cod_king_block_enabled?

module ShopifyServices
    class ShopifyAssetService
    BASE_URL = 'https://{store_name}/admin/api/2025-01/themes/{theme_id}/assets.json'

    def initialize(shop)
        @shop = shop
    end

    def fetch_asset
        uri = URI(BASE_URL.sub('{store_name}', @shop.shopify_domain).sub('{theme_id}', get_theme_id.to_s))
        uri.query = URI.encode_www_form({ 'asset[key]' => 'config/settings_data.json' })

        request = Net::HTTP::Get.new(uri)
        request['X-Shopify-Access-Token'] = @shop.shopify_token

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
        end

        if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
        else
        puts "Error fetching asset: #{response.message}"
        nil
        end
    end
    

    def get_theme_id
        @shop.init_session
        main_theme = ShopifyAPI::Theme.all.find { |th| th.role == 'main' }
        main_theme ? main_theme.id : nil
      end

    def is_cod_king_block_enabled?
        asset_response = fetch_asset
        return false unless asset_response

        value = asset_response.dig('asset', 'value')
        return false if value.nil?

        # Parse the JSON value and check if "cod-king" block is enabled
        parsed_value = JSON.parse(value)

        # Check if the "cod-king" block is disabled
        blocks = parsed_value.dig('current', 'blocks')
        blocks.any? { |_, block| block['type'].include?('cod-king') && block['disabled'] == false }
    end
    end
end