# frozen_string_literal: true

module CodFormAdmin
  # GET /cod_form/preview_frame — the bare page behind the designer's live preview (H.6, FRM-11).
  # Public: no auth, no shop data, no cookies. The admin posts the draft into the frame with
  # postMessage; the page imports the storefront core bundle and calls `core.preview(payload)`
  # (fixture cart, no network — the CSP has no connect-src).
  class PreviewFramesController < ActionController::Base
    CSP = "default-src 'none'; script-src https://cdn.shopify.com 'unsafe-inline'; style-src 'unsafe-inline'; " \
          "img-src https: data:; frame-ancestors https://admin.shopify.com https://*.myshopify.com 'self'"

    def show
      @asset_base = self.class.safe_asset_base(params[:asset_base], ENV.fetch("COD_FORM_EXTENSION_UUID", nil))
      response.set_header("Content-Security-Policy", CSP)
      response.headers.delete("X-Frame-Options") # frame-ancestors above is the rule
      response.set_header("Cache-Control", "no-store")
      response.set_header("X-Robots-Tag", "noindex")
      render :show, layout: false
    end

    # Accepted only when it is a Shopify CDN extension folder (H.6). When COD_FORM_EXTENSION_UUID
    # is set it must be this app's own extension; without it any extension folder on Shopify's
    # CDN passes, which is safe here because the frame is sandboxed (no origin, no cookies, no
    # network) and holds no shop data. Pure.
    def self.safe_asset_base(value, extension_uuid)
      base = value.to_s
      return nil if base.empty? || base.length > 300
      return nil if !extension_uuid.to_s.empty? && !base.start_with?("https://cdn.shopify.com/extensions/#{extension_uuid}/")
      return nil unless base.match?(%r{\Ahttps://cdn\.shopify\.com/extensions/[A-Za-z0-9\-]+/[A-Za-z0-9._\-/]*\z}) && !base.include?("..")

      base.end_with?("/") ? base : "#{base}/"
    end
  end
end
