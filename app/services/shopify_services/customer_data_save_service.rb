module ShopifyServices
    class CustomerDataSaveService < ShopifyServices::GraphqlService
      attr_reader :shop, :client

      # ShopifyServices::CustomerDataSaveService.call(@shop,customers)
  
      def initialize(client, shop, customers)
        @client = client
        @shop = shop
        @customers = customers.to_h.dig('data','customers','edges')
      end

      MAX_ATTEMPTS = 3

      def call
        if !@customers.blank?
          @customers.each do |customer|
             customer = customer.dig('node')
             save_with_retries(customer)
          end
        else
          puts 'No customers to process'
        end
      end

      private

      # Retry transient failures (deadlocks, connection drops, Shopify hiccups) up to MAX_ATTEMPTS.
      # On final failure, log and continue so one bad customer doesn't kill the whole pull.
      def save_with_retries(customer)
        attempts = 0
        begin
          attempts += 1
          ShopifyServices::CustomerSingleDataSaveService.call(@shop, customer)
        rescue => e
          if attempts < MAX_ATTEMPTS
            Rails.logger.warn(
              "[CustomerDataSave] retry #{attempts}/#{MAX_ATTEMPTS - 1} for shopify_customer_id=#{customer && customer['id']} " \
              "shop=#{@shop&.shopify_domain} #{e.class}: #{e.message}"
            )
            retry
          else
            Rails.logger.error(
              "[CustomerDataSave] giving up after #{attempts} attempts shopify_customer_id=#{customer && customer['id']} " \
              "shop=#{@shop&.shopify_domain} #{e.class}: #{e.message}"
            )
          end
        end
      end
    end
  end