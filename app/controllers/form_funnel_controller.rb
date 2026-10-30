# frozen_string_literal: true

# Public storefront ingest for the checkout/COD form funnel. The storefront
# widget POSTs a lightweight event (form_view / checkout_initiated) identifying
# the shop by its myshopify domain. Mirrors MetaEventsController: no Shopify
# session auth, CSRF skipped, and it ALWAYS returns 204 so the storefront never
# breaks — unknown shops and malformed payloads are silently ignored.
class FormFunnelController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:ingest]

  MAX_METADATA_KEYS = 20

  def ingest
    shop = Shop.find_by(shopify_domain: shop_domain)
    return head :no_content if shop.blank?

    event_type = params[:event_type].to_s
    return head :no_content unless FormFunnelEvent::EVENT_TYPES.include?(event_type)

    FormFunnelEvent.create!(
      shop_id: shop.id,
      session_token: params[:session_token].to_s.presence,
      event_type: event_type,
      occurred_at: parsed_occurred_at,
      metadata: capped_metadata
    )

    head :no_content
  rescue StandardError => e
    Rails.logger.warn("[FormFunnel] ingest error: #{e.class}: #{e.message}")
    head :no_content
  end

  private

  def shop_domain
    (params[:shop] || params[:domain]).to_s.strip.downcase.presence
  end

  def parsed_occurred_at
    Time.zone.parse(params[:occurred_at].to_s) || Time.current
  rescue StandardError
    Time.current
  end

  def capped_metadata
    raw = params[:metadata]
    return {} if raw.blank?

    hash = raw.respond_to?(:permit!) ? raw.permit!.to_h : raw.to_h
    hash.first(MAX_METADATA_KEYS).to_h
  rescue StandardError
    {}
  end
end
