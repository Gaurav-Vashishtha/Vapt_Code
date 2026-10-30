# frozen_string_literal: true

module CustomBranded
  # Auth + shop-resolution shell for the partner-facing branded WhatsApp portal
  # (/cb/:shop_domain). NOT Shopify-authenticated — access is gated by
  # partner-signed links:
  #
  #   /cb/<domain>?exp=<unix_ts>&sig=HMAC_SHA256(CB_PARTNER_SIGNING_SECRET, "<domain>|<exp>")
  #
  # The partner backend holds the shared secret and mints links for its own UI.
  # A raw Referer/Origin check is NOT the gate (browsers strip Referer, anyone
  # can forge it) — the HMAC is; Referer mismatches are logged as a soft
  # signal only. After the first verified hit the session cookie carries
  # access, so the portal's own XHRs don't re-send the params.
  #
  # Revoking the partner = rotating CB_PARTNER_SIGNING_SECRET.
  class BaseController < ApplicationController
    # Drops X-Frame-Options / sets CSP frame-ancestors so ParcelX can iframe
    # these pages (see the concern for the why).
    include CustomBranded::PartnerEmbeddable

    skip_before_action :verify_authenticity_token

    before_action :ensure_enabled!
    before_action :authenticate_partner_link!
    before_action :resolve_client!

    SESSION_KEY = 'cb_portal_domains'
    MAX_LINK_AGE = 7.days

    private

    def ensure_enabled!
      return if ActiveModel::Type::Boolean.new.cast(ENV['CB_PORTAL_ENABLED'])

      head :not_found
    end

    def signing_secret
      ENV['CB_PARTNER_SIGNING_SECRET'].to_s
    end

    def portal_domain_param
      params[:shop_domain].to_s.strip.downcase
    end

    def authenticate_partner_link!
      if signing_secret.blank?
        Rails.logger.error('[cb_portal] CB_PARTNER_SIGNING_SECRET is not set — portal locked')
        return head :not_found
      end

      # Already unlocked for this domain in this browser session.
      return if Array(session[SESSION_KEY]).include?(portal_domain_param)

      exp = params[:exp].to_i
      sig = params[:sig].to_s

      unless exp.positive? && sig.present?
        return render_unauthorized('This portal requires a signed access link.')
      end

      if Time.at(exp) < Time.current || Time.at(exp) > MAX_LINK_AGE.from_now
        return render_unauthorized('This access link has expired. Please open the portal again from your provider.')
      end

      expected = OpenSSL::HMAC.hexdigest('SHA256', signing_secret, "#{portal_domain_param}|#{exp}")
      unless ActiveSupport::SecurityUtils.secure_compare(expected, sig)
        Rails.logger.warn("[cb_portal] bad signature for domain=#{portal_domain_param}")
        return render_unauthorized('Invalid access link.')
      end

      log_referer_mismatch

      domains = Array(session[SESSION_KEY])
      # Cap so a wandering partner tab can't grow the cookie unboundedly.
      session[SESSION_KEY] = (domains + [portal_domain_param]).uniq.last(10)
    end

    # Soft signal only — never a gate.
    def log_referer_mismatch
      allowed = ENV['CB_PARTNER_ALLOWED_REFERERS'].to_s.split(',').map(&:strip).reject(&:blank?)
      return if allowed.empty?

      referer_host = URI.parse(request.referer.to_s).host rescue nil
      return if referer_host.present? && allowed.any? { |a| referer_host == a || referer_host.end_with?(".#{a}") }

      Rails.logger.warn("[cb_portal] referer mismatch domain=#{portal_domain_param} referer=#{request.referer.inspect}")
    end

    # The portal's tenant is a CustomBrandedClient — its own table, no shops
    # row, no Setting, nothing Shopify. First verified hit provisions it.
    def resolve_client!
      @client = CustomBranded::ClientProvisioner.call(domain: portal_domain_param)
      @client.update_column(:last_portal_access_at, Time.current)
    rescue CustomBranded::ClientProvisioner::InvalidDomain
      render_unauthorized('Invalid shop domain.')
    end

    # The shared Whatsapp::* concerns resolve their owner through this.
    def whatsapp_owner
      @client
    end

    def render_unauthorized(message)
      respond_to do |format|
        format.html { render plain: message, status: :unauthorized }
        format.json { render json: { error: message }, status: :unauthorized }
        format.any  { head :unauthorized }
      end
    end
  end
end
