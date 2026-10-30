# frozen_string_literal: true

module CodForm
  module Integrations
    # FRM-17: records the buyer's marketing consent on the Shopify customer after a form order
    # (customerSmsMarketingConsentUpdate / customerEmailMarketingConsentUpdate, API 2025-07).
    # Runs only when the buyer ticked the consent field. Never raises; never logs PII.
    #
    # The queries are validated by the GraphQL client against the dumped schema at run time
    # (F35), which is not available in this mirror.
    class MarketingConsent
      CHANNELS = %w[sms email].freeze

      # channels: subset of ["sms", "email"] (the consent field's `channels`).
      def self.call(shop, session, channels: CHANNELS)
        new(shop, session, channels).call
      rescue StandardError => e
        Rails.logger.warn("[codf/consent] shop=#{shop&.id} session=#{session&.id} failed: #{e.class}")
        false
      end

      # The submit stores the tick under one of these places; all are accepted.
      def self.given?(session)
        [session.custom_fields, session.contact, session.tracking].any? do |column|
          column.is_a?(Hash) && [true, "true", "1", 1, "on"].include?(column["marketing_consent"])
        end
      end

      def initialize(shop, session, channels)
        @shop = shop
        @session = session
        @channels = Array(channels).map(&:to_s) & CHANNELS
      end

      def call
        return false if @session.order_id.blank? || @channels.empty?

        @shop.init_session
        @client = ShopifyAPI::GraphQL.client
        customer = fetch_customer
        return false if customer.nil?

        now = Time.current.utc.iso8601
        update_sms(customer[:id], now) if @channels.include?("sms") && customer[:phone].present?
        update_email(customer[:id], now) if @channels.include?("email") && customer[:email].present?
        true
      end

      private

      def fetch_customer
        query = @client.parse <<-'GRAPHQL'
          query ($id: ID!) {
            order(id: $id) {
              customer { id phone email }
            }
          }
        GRAPHQL
        response = @client.query(query, variables: { id: "gid://shopify/Order/#{@session.order_id}" })
        customer = response&.data&.order&.customer
        return nil if customer.nil?

        { id: customer.id, phone: customer.phone, email: customer.email }
      end

      def update_sms(customer_id, now)
        query = @client.parse <<-'GRAPHQL'
          mutation ($input: CustomerSmsMarketingConsentUpdateInput!) {
            customerSmsMarketingConsentUpdate(input: $input) {
              userErrors { field message }
            }
          }
        GRAPHQL
        @client.query(query, variables: { input: {
                        customerId: customer_id,
                        smsMarketingConsent: { marketingState: "SUBSCRIBED", marketingOptInLevel: "SINGLE_OPT_IN",
                                               consentUpdatedAt: now }
                      } })
      end

      def update_email(customer_id, now)
        query = @client.parse <<-'GRAPHQL'
          mutation ($input: CustomerEmailMarketingConsentUpdateInput!) {
            customerEmailMarketingConsentUpdate(input: $input) {
              userErrors { field message }
            }
          }
        GRAPHQL
        @client.query(query, variables: { input: {
                        customerId: customer_id,
                        emailMarketingConsent: { marketingState: "SUBSCRIBED", marketingOptInLevel: "SINGLE_OPT_IN",
                                                 consentUpdatedAt: now }
                      } })
      end
    end
  end
end
