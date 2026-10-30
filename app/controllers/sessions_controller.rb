# frozen_string_literal: true

# Mints the offline Admin API token on first install, using the embedded
# request's session token (JWT). HomeController#index defers to this when the
# shop has no token yet, so first paint isn't blocked on the (slow) OAuth
# token-exchange.
#
# We can't use ShopifyApp::Authenticated here: its session activation expects an
# offline token to already exist — and minting that token is exactly this
# endpoint's job. So we authenticate the session-token JWT manually (signature +
# claims are verified by ShopifyApp::JWT) and resolve the shop from it.
class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :bootstrap, raise: false

  def bootstrap
    token = bearer_token
    return render(json: { error: 'missing_session_token' }, status: :unauthorized) if token.blank?

    domain = shopify_domain_from_jwt(token)
    return render(json: { error: 'invalid_session_token' }, status: :unauthorized) if domain.blank?

    shop = Shop.find_by(shopify_domain: domain)
    return render(json: { error: 'shop_not_found' }, status: :not_found) if shop.blank?

    # We already minted a token for this shop moments ago and it's being asked
    # for again, which means the fresh one failed too. Another exchange would
    # produce another dead token and another reload, so stop here and let the
    # client fall back to its manual reload prompt.
    if ShopifyServices::OfflineTokenService.remint_attempted?(shop)
      Rails.logger.error("[SessionBootstrap] re-mint loop guard tripped shop=#{domain}")
      return render(json: { ok: false, error: 'token_unrecoverable' }, status: :service_unavailable)
    end

    ShopifyServices::OfflineTokenService.ensure_fresh!(shop, session_token: token)
    # Armed on a completed exchange rather than a good outcome: an exchange that
    # returns an unusable token is a permanent condition, and leaving the guard
    # disarmed there lets the client's retries re-exchange on a 30s cadence
    # forever. Exchanges that raise are transient and stay retryable.
    ShopifyServices::OfflineTokenService.mark_remint_attempted(shop)

    # ok:true makes the client reload into the full flow, so only say it once
    # the shop would survive that reload. A response missing expires_in leaves
    # a token that `usable?` rejects, and the reload lands back on this shell.
    unless ShopifyServices::OfflineTokenService.usable?(shop)
      Rails.logger.error("[SessionBootstrap] exchange produced an unusable token shop=#{domain}")
      return render(json: { ok: false, error: 'token_exchange_failed' }, status: :service_unavailable)
    end

    render json: { ok: true }
  rescue ShopifyServices::OfflineTokenService::Error => e
    Rails.logger.warn("[SessionBootstrap] token exchange failed shop=#{domain}: #{e.class}: #{e.message}")
    # Transient (slow/timeout/5xx from Shopify): client retries and, if it keeps
    # failing, shows a "reload to finish setup" prompt.
    render json: { ok: false, error: 'token_exchange_failed' }, status: :service_unavailable
  end

  private

  def bearer_token
    request.headers['Authorization'].to_s.sub(/\ABearer\s+/, '').presence
  end

  def shopify_domain_from_jwt(token)
    ShopifyApp::JWT.new(token).shopify_domain
  rescue StandardError => e
    Rails.logger.warn("[SessionBootstrap] JWT decode failed: #{e.class}: #{e.message}")
    nil
  end
end
