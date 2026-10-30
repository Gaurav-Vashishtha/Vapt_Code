# frozen_string_literal: true

module Whatsapp
  module Inbox
    class AgentResolver
      TOUCH_INTERVAL = 5.minutes

      def self.call(shop:, request:)
        new(shop, request).call
      end

      def initialize(shop, request)
        @shop = shop
        @request = request
      end

      def call
        agent = find_or_create(shopify_user_id)
        touch_last_seen(agent)
        agent
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::AgentResolver] shop=#{@shop&.id} #{e.class}: #{e.message}")
        store_team_fallback
      end

      private

      def shopify_user_id
        from_env = @request.env['jwt.shopify_user_id'].to_i
        return from_env if from_env.positive?

        from_token
      end

      # shopify_app 18 only exposes the session token's `sub` through its JWT class
      # (shopify_api 9.5 has no Auth::JwtPayload). Re-verifying here is cheap and
      # the domain check stops a token from another shop naming an agent in this one.
      def from_token
        token = @request.headers['Authorization'].to_s[/\ABearer (.+)\z/, 1]
        return 0 if token.blank?

        jwt = ShopifyApp::JWT.new(token)
        return 0 unless jwt.shopify_domain.to_s == @shop.shopify_domain.to_s

        jwt.shopify_user_id.to_i
      rescue StandardError
        0
      end

      def find_or_create(uid)
        uid = WhatsappInboxAgent::STORE_TEAM_ID unless uid.positive?
        attrs = { shop_id: @shop.id, shopify_user_id: uid }
        WhatsappInboxAgent.find_by(attrs) || WhatsappInboxAgent.create!(attrs)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        WhatsappInboxAgent.find_by!(attrs)
      end

      def touch_last_seen(agent)
        return if agent.last_seen_at.present? && agent.last_seen_at > TOUCH_INTERVAL.ago

        now = Time.current
        agent.update_column(:last_seen_at, now)
      end

      def store_team_fallback
        find_or_create(WhatsappInboxAgent::STORE_TEAM_ID)
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::AgentResolver] store team fallback shop=#{@shop&.id} #{e.class}: #{e.message}")
        WhatsappInboxAgent.new(shop_id: @shop&.id, shopify_user_id: WhatsappInboxAgent::STORE_TEAM_ID)
      end
    end
  end
end
