module NetworkServices
  # Subscribes a single shop to the orders/create webhook at the EventBridge
  # ARN configured on its RabbitPayConfig. Idempotent:
  #   - skips if the shop already has orders/create pointing at this ARN
  #   - destroys any orders/create webhook pointing elsewhere and creates a new one
  #   - creates from scratch if none exists
  #
  # Usage:
  #   NetworkServices::RabbitPayOrderCreateWebhookSubscribeService.call('foo.myshopify.com')
  #
  # Returns a Result struct so callers can branch on status without parsing logs.
  #   r.status  => :created | :replaced | :already | :no_config | :no_arn | :no_shop | :failed
  #   r.address => the full ARN we tried to subscribe to (nil for :no_config / :no_arn)
  #   r.message => human-readable detail (Shopify error, exception, etc.)
  class RabbitPayOrderCreateWebhookSubscribeService < ApplicationService
    TOPIC = 'orders/create'.freeze
    REGION_PREFIX = 'arn:aws:events:us-east-2::event-source/'.freeze
    FORMAT = 'json'.freeze

    Result = Struct.new(:status, :shopify_domain, :address, :message, keyword_init: true)

    def initialize(shopify_domain)
      @shopify_domain = shopify_domain.to_s.strip
    end

    def call
      return build_result(:no_shop, message: 'shopify_domain is blank') if @shopify_domain.blank?

      config = RabbitPayConfig.find_by(shopify_domain: @shopify_domain)
      return build_result(:no_config, message: "no RabbitPayConfig for #{@shopify_domain}") unless config

      arn_path = config.event_source_arn.to_s.strip
      return build_result(:no_arn, message: 'RabbitPayConfig.event_source_arn is blank') if arn_path.blank?

      target_address = "#{REGION_PREFIX}#{arn_path}"

      shop = Shop.find_by(shopify_domain: @shopify_domain)
      return build_result(:no_shop, address: target_address, message: 'shop not found') unless shop

      subscribe(shop, target_address)
    rescue StandardError => e
      build_result(:failed, message: "#{e.class}: #{e.message}")
    end

    private

    def subscribe(shop, target_address)
      shop.init_session

      existing = ShopifyAPI::Webhook.find(:all)
      orders_create_hooks = existing.is_a?(Array) ? existing.select { |w| w.topic == TOPIC } : []

      if orders_create_hooks.any? { |w| w.address == target_address }
        return build_result(:already, address: target_address, message: 'already subscribed')
      end

      destroyed_addresses = orders_create_hooks.map(&:address)
      orders_create_hooks.each(&:destroy)

      webhook = ShopifyAPI::Webhook.new(topic: TOPIC, address: target_address, format: FORMAT)
      if webhook.save
        if destroyed_addresses.any?
          build_result(
            :replaced,
            address: target_address,
            message: "replaced #{destroyed_addresses.size} stale subscription(s): #{destroyed_addresses.join(', ')}"
          )
        else
          build_result(:created, address: target_address, message: 'created')
        end
      else
        msg = webhook.errors.full_messages.join('; ').presence || 'save returned false'
        build_result(:failed, address: target_address, message: msg)
      end
    end

    def build_result(status, address: nil, message: nil)
      Result.new(status: status, shopify_domain: @shopify_domain, address: address, message: message)
    end
  end
end
