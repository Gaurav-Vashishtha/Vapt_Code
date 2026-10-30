# frozen_string_literal: true

module Api
  module Sidekick
    # Shared behaviour for the Shopify Sidekick data tools
    # (payment-customization-js/extensions/codk-sidekick-data).
    #
    # Sidekick limits: responses over ~4,000 tokens are rejected and tools slower
    # than ~1s may be skipped, so lists are capped and heavy reads are cached.
    # Errors come back as 200 + { error, hint } so Sidekick can explain them to
    # the merchant instead of reporting a generic failure.
    class BaseController < AuthenticatedController
      # Requests are authenticated by the Shopify session token (Bearer), not a
      # cookie session, so CSRF does not apply and would reject every POST.
      skip_forgery_protection

      MAX_RESULTS = 15
      DEFAULT_RESULTS = 10
      CACHE_TTL = 5.minutes

      before_action :require_shop

      rescue_from StandardError do |error|
        raise error if Rails.env.test?

        Rails.logger.error("[Sidekick] #{self.class.name}##{action_name} shop=#{@shop&.id}: #{error.class} #{error.message}")
        render json: {
          error: 'COD King could not load this data right now.',
          hint: 'Ask the merchant to try again in a moment or open the COD King app directly.'
        }
      end

      private

      def require_shop
        return if @shop

        render json: { error: 'This store is not connected to COD King.', hint: 'Reinstall or open the COD King app.' }
      end

      def result_limit
        limit = params[:first].to_i
        return DEFAULT_RESULTS if limit <= 0

        [limit, MAX_RESULTS].min
      end

      def window_days(default: 30, max: 90)
        days = params[:days].to_i
        days = default if days <= 0
        [days, max].min
      end

      def resource_link(type:, id:, name:, meta:)
        {
          type: 'resource_link',
          uri: "gid://application/#{type}/#{id}",
          name: name,
          mimeType: "application/#{type}",
          _meta: meta.compact
        }
      end

      # TwilioLog#status is a plain Twilio status ("sent", "delivered", ...) on
      # success, but failed sends store the provider's error hash via #inspect,
      # e.g. {"status"=>"fail", "errors"=>"WhatsApp not integrated:91..."}.
      def twilio_status(raw)
        text = raw.to_s
        return [text.presence, nil] unless text.start_with?('{')

        error = text[/"errors?"=>"([^"]+)"/, 1] || text[/"message"=>"([^"]+)"/, 1]
        ['failed', error]
      end

      def cached(key, &block)
        Rails.cache.fetch(['sidekick', key, @shop.id, params[:days]].compact.join(':'), expires_in: CACHE_TTL, &block)
      end
    end
  end
end
