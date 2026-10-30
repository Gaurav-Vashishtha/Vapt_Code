module ShopifyServices
    class PaymentCustomizationService < ShopifyServices::GraphqlService
      attr_reader :shop, :client

      # ShopifyServices::PaymentCustomizationService.call(
      #   @shop , 'Cash on Delivery'
      # )
  
      def initialize(client, shop,payment_name)
        @client = client
        @shop = shop
        @payment_name = payment_name
      end
  
      # COD Form (PRE-3, ARCHITECTURE.md I.6): after the function configuration is written as
      # before, the key `hideCodAtCheckout: true` is merged into it when the shop has
      # "COD only through the form" on and the form is live. Shops without that toggle get exactly
      # the same configuration as before (the key is absent).
      def call
        result = configure_payment_customization
        add_cod_form_hide_cod_key if result.present?
        result
      end

      private

      def configure_payment_customization
        # if Rails.env.development?
        #   return nil
        # end
        if @shop.setting.payment_customization_id.blank?
          payment_customization_id = ShopifyServices::PaymentFunctionCreateService.call(@shop)
          @shop.setting.update(payment_customization_id: payment_customization_id, payment_method_name: @payment_name)
        end
        if !@shop.setting.payment_customization_id.blank?
            params = ShopifyServices::PaymentFunctionMetafieldService.call(@shop,@shop.setting.payment_customization_id ,  @payment_name)
            if params.blank?
              payment_customization_id = ShopifyServices::PaymentFunctionCreateService.call(@shop)
              @shop.setting.update(payment_customization_id: payment_customization_id, payment_method_name: @payment_name)
              params = ShopifyServices::PaymentFunctionMetafieldService.call(@shop,@shop.setting.payment_customization_id ,  @payment_name)
              SlackNotifyJob.perform_async(
                ":rage:  (#{Rails.env})\n  *ShopifyServices::PaymentFunctionMetafieldService attempt 2#{params}"
              )
              return params 
            else
              return params
            end
        end
      end

      COD_FORM_CONFIG_NAMESPACE = "payment-customization"
      COD_FORM_CONFIG_KEY = "function-configuration"

      # Never raises and never changes the return value of #call.
      def add_cod_form_hide_cod_key
        return unless defined?(CodForm::MetafieldSyncService) && CodForm::MetafieldSyncService.hide_cod_at_checkout?(@shop)

        owner_id = @shop.setting.payment_customization_id
        query = @client.parse <<-'GRAPHQL'
          query ($id: ID!) {
            paymentCustomization(id: $id) {
              metafield(namespace: "payment-customization", key: "function-configuration") {
                value
              }
            }
          }
        GRAPHQL
        current = @client.query(query, variables: { id: owner_id })&.data&.payment_customization&.metafield&.value
        return if current.blank?

        config = JSON.parse(current)
        return if config["hideCodAtCheckout"] == true

        ShopifyServices::MetafieldsSetService.new(@client, @shop).call(
          [{
            ownerId: owner_id,
            namespace: COD_FORM_CONFIG_NAMESPACE,
            key: COD_FORM_CONFIG_KEY,
            value: config.merge("hideCodAtCheckout" => true).to_json,
            type: "json"
          }]
        )
      rescue StandardError => e
        Rails.logger.warn("[PaymentCustomizationService] hideCodAtCheckout not set shop_id=#{@shop&.id} #{e.class}")
      end
    end
  end
