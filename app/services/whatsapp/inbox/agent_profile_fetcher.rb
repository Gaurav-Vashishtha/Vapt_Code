# frozen_string_literal: true

module Whatsapp
  module Inbox
    class AgentProfileFetcher
      RESYNC_AFTER = 7.days
      TIMEOUT_SECONDS = 4
      ONLINE_TOKEN_TYPE = 'urn:shopify:params:oauth:token-type:online-access-token'

      def self.call(shop:, agent:, session_token:)
        new(shop, agent, session_token).call
      end

      def initialize(shop, agent, session_token)
        @shop = shop
        @agent = agent
        @session_token = session_token
      end

      def call
        return @agent unless due?

        attrs = { profile_synced_at: Time.current, updated_at: Time.current }
        attrs.merge!(profile_attrs(fetch_associated_user))
        @agent.update_columns(attrs)
        @agent
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Inbox::AgentProfileFetcher] shop=#{@shop&.id} agent=#{@agent&.id} #{e.class}: #{e.message}")
        mark_attempted
        @agent
      end

      private

      def due?
        @agent&.persisted? &&
          @agent.shopify_user_id.to_i.positive? &&
          @session_token.present? &&
          (@agent.profile_synced_at.nil? || @agent.profile_synced_at < RESYNC_AFTER.ago)
      end

      # Shopify token exchange: the response's `associated_user` carries the staff
      # member's name/email. The online access_token in the same response is
      # deliberately dropped and never logged or stored.
      def fetch_associated_user
        resp = HTTParty.post(
          "https://#{@shop.shopify_domain}/admin/oauth/access_token",
          headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
          body: {
            client_id: ShopifyApp.configuration.api_key,
            client_secret: ShopifyApp.configuration.secret,
            grant_type: ShopifyServices::OfflineTokenService::TOKEN_EXCHANGE_GRANT,
            subject_token: @session_token,
            subject_token_type: ShopifyServices::OfflineTokenService::ID_TOKEN_TYPE,
            requested_token_type: ONLINE_TOKEN_TYPE
          }.to_json,
          timeout: TIMEOUT_SECONDS
        )
        unless resp.success?
          Rails.logger.warn("[Whatsapp::Inbox::AgentProfileFetcher] token exchange status=#{resp.code} shop=#{@shop.id}")
          return nil
        end

        user = JSON.parse(resp.body.to_s)['associated_user']
        user.is_a?(Hash) ? user : nil
      rescue JSON::ParserError
        nil
      end

      def profile_attrs(user)
        return {} unless user && user['id'].to_i == @agent.shopify_user_id.to_i

        attrs = {}
        name = [user['first_name'], user['last_name']].map { |v| v.to_s.strip }.reject(&:empty?).join(' ')
        attrs[:name] = name.truncate(255) if name.present?
        attrs[:email] = user['email'].to_s.strip.truncate(255) if user['email'].present?
        attrs[:account_owner] = user['account_owner'] == true if user.key?('account_owner')
        attrs
      end

      def mark_attempted
        @agent.update_column(:profile_synced_at, Time.current) if @agent&.persisted?
      rescue StandardError
        nil
      end
    end
  end
end
