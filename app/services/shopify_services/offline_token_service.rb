require 'httparty'

module ShopifyServices
  # Keeps a shop's offline Admin API access token valid.
  #
  # Shopify stopped accepting legacy *non-expiring* offline tokens, so we use
  # *expiring* offline tokens (access token ~1h + refresh token ~90d) and:
  #   - migrate a legacy/non-expiring token → expiring via OAuth token exchange,
  #     using the embedded request's session token (id_token). No merchant
  #     re-consent. Irreversible: Shopify revokes the old token on exchange.
  #   - refresh an expiring token via the refresh_token grant when it's near/past
  #     expiry. Refresh tokens rotate, so concurrent refreshes are collapsed under
  #     a row lock + "recently refreshed" guard.
  #
  # All persistence uses `update_columns` (no AR callbacks): routine hourly
  # refreshes must NOT re-fire Shop#bootstrap_rto_intelligence_on_install, and we
  # bust the Shop domain cache explicitly since `update_columns` skips it.
  #
  #   ShopifyServices::OfflineTokenService.ensure_fresh!(shop, session_token: params[:id_token])
  class OfflineTokenService < ApplicationService
    class Error < StandardError
      attr_reader :http_status
      def initialize(msg = nil, http_status: nil)
        @http_status = http_status
        super(msg)
      end
    end
    # Raised when there's no usable token and no way to get one without the
    # merchant re-opening the app (dead refresh token, no session token).
    class NeedsReauth < Error; end

    SKEW = 120                # refresh proactively when <2 min of life remains
    RECENTLY_REFRESHED = 30   # seconds — collapse a refresh stampede
    REMINT_MARKER_TTL = 5.minutes

    TOKEN_EXCHANGE_GRANT = 'urn:ietf:params:oauth:grant-type:token-exchange'.freeze
    ID_TOKEN_TYPE        = 'urn:ietf:params:oauth:token-type:id_token'.freeze
    OFFLINE_TOKEN_TYPE   = 'urn:shopify:params:oauth:token-type:offline-access-token'.freeze

    def initialize(shop, session_token: nil)
      @shop = shop
      @session_token = session_token
    end

    def call
      self.class.ensure_fresh!(@shop, session_token: @session_token)
    end

    class << self
      # Returns :fresh, :migrated, :refreshed, or :legacy_unmigrated.
      # Raises NeedsReauth only when an expiring token's refresh path is dead and
      # no session token is available (callers in background context must rescue).
      def ensure_fresh!(shop, session_token: nil)
        return :fresh if token_fresh?(shop)

        result = nil
        shop.with_lock do
          shop.reload
          if token_fresh?(shop) || recently_refreshed?(shop)
            result = :fresh
          elsif session_token.present? && (shop.shopify_token_expires_at.nil? || !refresh_token_usable?(shop))
            migrate_via_session_token!(shop, session_token)
            result = :migrated
          elsif refresh_token_usable?(shop)
            refresh!(shop)
            result = :refreshed
          elsif session_token.present?
            migrate_via_session_token!(shop, session_token)
            result = :migrated
          elsif shop.shopify_token_expires_at.nil? && shop.shopify_refresh_token.blank?
            # Legacy non-expiring token; can't migrate without a session token.
            # Self-heals on the shop's next embedded admin load.
            result = :legacy_unmigrated
          else
            raise NeedsReauth, "shop=#{shop.shopify_domain} expiring token unusable and no session token"
          end
        end
        result
      end

      # Exchange the embedded session token for an EXPIRING offline token.
      # Irreversible: the existing (non-expiring) token is revoked by Shopify.
      def migrate_via_session_token!(shop, session_token)
        body = post_token_request(shop,
          client_id: client_id,
          client_secret: client_secret,
          grant_type: TOKEN_EXCHANGE_GRANT,
          subject_token: session_token,
          subject_token_type: ID_TOKEN_TYPE,
          requested_token_type: OFFLINE_TOKEN_TYPE,
          expiring: '1'
        )
        Rails.logger.info("[OfflineToken] migrated shop=#{shop.shopify_domain} to expiring token (old token revoked)")
        persist!(shop, body)
        :migrated
      end

      # Rotate an expiring offline token using its refresh token.
      def refresh!(shop)
        body = post_token_request(shop,
          client_id: client_id,
          client_secret: client_secret,
          grant_type: 'refresh_token',
          refresh_token: shop.shopify_refresh_token
        )
        Rails.logger.info("[OfflineToken] refreshed shop=#{shop.shopify_domain}")
        persist!(shop, body)
        :refreshed
      rescue Error => e
        # A rejected refresh token means the merchant must re-open the app to
        # re-mint via token exchange. Clear the dead refresh token and signal.
        if [400, 401].include?(e.http_status)
          shop.update_columns(shopify_refresh_token: nil, shopify_refresh_token_expires_at: nil)
          Shop.expire_cache(shop.shopify_domain)
          raise NeedsReauth, "shop=#{shop.shopify_domain} refresh token rejected (#{e.http_status})"
        end
        raise
      end

      # True when the shop's offline token can serve Admin API calls THIS request
      # WITHOUT a client session token — i.e. it's a fresh expiring token, or an
      # expired one we can still refresh via its refresh token. Returns false for:
      # no token, a legacy non-expiring token (Shopify now 403s these), or an
      # expired token whose refresh token is dead — all of which must be
      # (re)minted via a client session token (see SessionsController#bootstrap).
      def usable?(shop)
        token_fresh?(shop) || refresh_token_usable?(shop)
      end

      # Freshness here is only ever a timestamp comparison, so a token Shopify
      # revoked out of band (reinstall, scope change, a competing token
      # exchange) still reads as usable and every Admin API call 401s forever.
      # Callers that see a 401 clear the metadata through here: `usable?` then
      # returns false and the next embedded load re-mints via token exchange.
      def invalidate!(shop, failed_token: nil)
        invalidated = false
        shop.with_lock do
          shop.reload
          # Only clear the metadata belonging to the token that actually failed.
          # A sibling request that minted a replacement while we were failing
          # must not have its work thrown away — concurrent 401s on one shop
          # otherwise revoke each other's tokens in a ping-pong. Comparing the
          # token itself (rather than how recently it was written) keeps this
          # honest when the failing token is one THIS request just refreshed.
          if failed_token.nil? || shop.shopify_token == failed_token
            shop.update_columns(
              shopify_token_expires_at: nil,
              shopify_refresh_token: nil,
              shopify_refresh_token_expires_at: nil,
              shopify_token_refreshed_at: nil,
              updated_at: Time.current
            )
            invalidated = true
          end
        end
        Shop.expire_cache(shop.shopify_domain) if invalidated
        invalidated
      end

      # Call after an Admin API 401. If the shop still holds a usable refresh
      # token, rotate it and return true so the caller can retry ONCE with the
      # new token. Otherwise clear the stale metadata (invalidate!) and return
      # false: only the merchant re-opening the app can fix it.
      def recover_from_unauthorized!(shop, failed_token: nil)
        shop.reload
        if refresh_token_usable?(shop) && (failed_token.nil? || shop.shopify_token == failed_token)
          begin
            shop.with_lock { refresh!(shop) }
            return true
          rescue Error => e
            Rails.logger.warn("[OfflineToken] recover refresh failed shop=#{shop.shopify_domain}: #{e.message}")
          end
        elsif failed_token.present? && shop.shopify_token != failed_token
          return true # a sibling request already minted a replacement
        end
        invalidate!(shop, failed_token: failed_token)
        false
      end

      # Set only after a mint SUCCEEDS, so a shop that comes back asking for
      # another one is telling us the fresh token failed too — minting again
      # would just bounce the merchant around the bootstrap/reload cycle.
      # Transient exchange failures leave it unset and stay retryable.
      def remint_attempted?(shop)
        Rails.cache.read(remint_marker_key(shop)).present?
      end

      def mark_remint_attempted(shop)
        Rails.cache.write(remint_marker_key(shop), true, expires_in: REMINT_MARKER_TTL)
      end

      def clear_remint_marker(shop)
        Rails.cache.delete(remint_marker_key(shop))
      end

      private

      def remint_marker_key(shop)
        "shop/#{shop.shopify_domain}/offline_token_remint"
      end

      def token_fresh?(shop)
        shop.shopify_token_expires_at.present? &&
          shop.shopify_token_expires_at > Time.current + SKEW
      end

      def recently_refreshed?(shop)
        shop.shopify_token_refreshed_at.present? &&
          shop.shopify_token_refreshed_at > RECENTLY_REFRESHED.seconds.ago
      end

      def refresh_token_usable?(shop)
        shop.shopify_refresh_token.present? &&
          shop.shopify_refresh_token_expires_at.present? &&
          shop.shopify_refresh_token_expires_at > Time.current + SKEW
      end

      def persist!(shop, body)
        now = Time.current
        access_token = body['access_token']
        raise Error, "shop=#{shop.shopify_domain} token response missing access_token" if access_token.blank?

        shop.update_columns(
          shopify_token: access_token,
          shopify_refresh_token: body['refresh_token'].presence || shop.shopify_refresh_token,
          shopify_token_expires_at: now + body['expires_in'].to_i.seconds,
          shopify_refresh_token_expires_at:
            (body['refresh_token_expires_in'].present? ? now + body['refresh_token_expires_in'].to_i.seconds : shop.shopify_refresh_token_expires_at),
          shopify_token_refreshed_at: now,
          updated_at: now
        )
        # update_columns skips after_update :cleanup_related_records — bust the
        # Shop domain cache so cached objects don't keep serving the old token.
        Shop.expire_cache(shop.shopify_domain)

        # Keep the RTO ShopInstallation token in sync (plain UPDATE, no callbacks
        # or backfill re-enqueue). The previously stored token is now revoked.
        begin
          ShopInstallation.active.where(shop_id: shop.id).update_all(access_token: access_token, updated_at: now)
        rescue => e
          Rails.logger.warn("[OfflineToken] ShopInstallation sync failed shop=#{shop.shopify_domain}: #{e.message}")
        end
        begin
          CustomerSyncState.schedule_recheck(shop.id)
        rescue => e
          Rails.logger.warn("[OfflineToken] customer sync recheck not scheduled shop=#{shop.shopify_domain}: #{e.message}")
        end
      end

      def post_token_request(shop, params)
        resp = HTTParty.post(
          token_url(shop.shopify_domain),
          headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
          body: params.to_json,
          # Safety-net bound so a genuinely hung Shopify connection can't stall an
          # embedded page load forever (this runs inline on first install, under a
          # row lock). Kept generous on read so a slow-but-successful exchange
          # isn't turned into a failure. On timeout we raise a catchable Error
          # instead of letting a Net::*Timeout escape uncaught.
          open_timeout: 5,
          read_timeout: 30
        )
        parsed = begin
          JSON.parse(resp.body.presence || '{}')
        rescue JSON::ParserError
          {}
        end
        unless resp.success?
          Rails.logger.warn("[OfflineToken] token request failed shop=#{shop.shopify_domain} status=#{resp.code} body=#{resp.body}")
          raise Error.new("Shopify token endpoint #{resp.code}: #{resp.body}", http_status: resp.code)
        end
        parsed
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        Rails.logger.warn("[OfflineToken] token request timed out shop=#{shop.shopify_domain}: #{e.class}")
        raise Error.new("Shopify token endpoint timeout: #{e.class}", http_status: 504)
      end

      def token_url(domain)
        "https://#{domain}/admin/oauth/access_token"
      end

      def client_id
        ShopifyApp.configuration.api_key
      end

      def client_secret
        ShopifyApp.configuration.secret
      end
    end
  end
end
