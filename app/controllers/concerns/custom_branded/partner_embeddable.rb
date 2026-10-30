# frozen_string_literal: true

module CustomBranded
  # Lets the partner (ParcelX) embed the custom-branded pages in an <iframe>
  # on any site.
  #
  # Rails ships `X-Frame-Options: SAMEORIGIN` on every response
  # (action_dispatch.default_headers), which is what produced
  #   "Refused to display 'https://app.codking.tech/' in a frame because it
  #    set 'X-Frame-Options' to 'sameorigin'"
  # on the partner's dashboard. For the /cb pages we drop that header and
  # send `Content-Security-Policy: frame-ancestors *` so ANY origin may frame
  # them (product decision 2026-09-17: no frame-ancestors allow-list for cb
  # pages). Access itself is still gated by the HMAC-signed link.
  #
  # This runs as a *prepended before_action* (not an after_action) on purpose:
  # halting before_actions (expired link -> 401, portal disabled -> 404) skip
  # after_actions, so those error pages would still carry SAMEORIGIN and show
  # the browser's "refused to connect" box instead of our message.
  #
  # Cookies: the session cookie set after the first signed hit is already
  # `SameSite=None; Secure` (ShopifyApp::SameSiteCookieMiddleware, embedded
  # app), so it is sent from inside a cross-site iframe as well.
  module PartnerEmbeddable
    extend ActiveSupport::Concern

    included do
      prepend_before_action :allow_partner_iframe
    end

    private

    def allow_partner_iframe
      response.headers.delete('X-Frame-Options')
      response.set_header('Content-Security-Policy', 'frame-ancestors *')
    end
  end
end
