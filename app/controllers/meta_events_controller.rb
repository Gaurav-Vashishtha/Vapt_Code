# frozen_string_literal: true

# Public ingest for the COD King web pixel (extensions/cod-king-web-pixel). The pixel
# batches Meta events and POSTs them here; we hash the PII, attach the request IP/UA and
# forward straight to the Conversions API within this request — no background queue.
#
# Mirrors FormFunnelController: no Shopify session, CSRF skipped, and it ALWAYS returns
# 204 so an ingest problem can never surface as a storefront error.
class MetaEventsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]

  # ParamsWrapper otherwise copies the whole batch under a `meta_event` key, doubling
  # the parsed params and the logged line on the app's highest-volume endpoint.
  wrap_parameters false

  MAX_EVENTS_PER_REQUEST = 50

  def create
    shop = Shop.find_by(shopify_domain: shop_domain)
    return reject("shop_not_found", shop_domain) if shop.blank?

    unless MetaEvents::Token.valid?(shop, request.headers["X-Codk-Meta-Token"])
      return reject("bad_token", shop.shopify_domain, "header_present=#{request.headers['X-Codk-Meta-Token'].present?}")
    end

    unless shop.setting&.meta_events_active?
      return reject("inactive", shop.shopify_domain, gate_detail(shop))
    end

    events = incoming_events
    return reject("empty_batch", shop.shopify_domain, "raw=#{params[:events].class}") if events.empty?

    # Synchronous by design: the Conversions API call happens inline, before this
    # responds. CapiClient caps it at MetaEvents::CapiClient::TIMEOUT_SECONDS so a slow
    # Graph API can't hold the Puma thread open.
    MetaEvents::Dispatcher.new(
      shop: shop,
      events: events,
      client_ip: request.remote_ip,
      client_user_agent: request.user_agent.to_s.presence,
    ).call

    head :no_content
  rescue StandardError => e
    Rails.logger.warn("[MetaEvents] ingest error: #{e.class}: #{e.message}")
    head :no_content
  end

  private

  def reject(reason, domain, detail = nil)
    Rails.logger.info(
      "[MetaEvents] rejected reason=#{reason} shop=#{domain.presence || 'blank'} " \
      "ip=#{request.remote_ip}#{detail.present? ? " #{detail}" : ''}",
    )
    head :no_content
  end

  def gate_detail(shop)
    setting = shop.setting
    return "setting=nil" if setting.blank?
    return "column=missing" unless setting.has_attribute?(:meta_events_enabled)

    "enabled=#{setting[:meta_events_enabled]} conversion=#{setting[:conversion_tracking]} " \
      "pixel_id=#{setting.pixel_id.present?} pixel_token=#{setting.pixel_token.present?}"
  end

  def shop_domain
    params[:shop].to_s.strip.downcase.presence
  end

  # Deliberately permit! then take the raw hash: the payload is a passthrough to
  # MetaEvents::EventBuilder, which allow-lists every key it forwards to Meta.
  # as_json is what makes it a plain String-keyed Hash — Sidekiq's strict_args rejects
  # HashWithIndifferentAccess job arguments.
  def incoming_events
    raw = params[:events]
    return [] unless raw.is_a?(Array)

    raw.first(MAX_EVENTS_PER_REQUEST).filter_map do |event|
      next unless event.respond_to?(:to_h)

      hash = event.respond_to?(:permit!) ? event.permit!.to_h : event.to_h
      hash.as_json.presence
    end
  end
end
