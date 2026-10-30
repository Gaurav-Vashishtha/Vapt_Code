# frozen_string_literal: true

class Api::CustomAbandonedCartsController < ApplicationController
  include ShippingPublicApiOrigin

  skip_before_action :verify_authenticity_token, only: [:create]
  before_action :verify_shipping_public_api_origin!, only: [:create]

  # Slack rejects blocks over ~4000 chars; leave room for the header and fences.
  MAX_SLACK_TEXT = 3500

  def create
    SlackNotifyJob.perform_async(slack_text(request_payload))
    render json: { ok: true }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[CustomAbandonedCart] #{e.class}: #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  private

  def request_payload
    json = parsed_json_body
    return json if json

    # wrap_parameters mirrors a JSON body under the controller name; drop that copy.
    filtered = params.except(:controller, :action, :format, :custom_abandoned_cart).to_unsafe_h
    return filtered if filtered.present?

    request.raw_post.to_s
  end

  def parsed_json_body
    body = request.raw_post.to_s
    return nil if body.blank?

    parsed = JSON.parse(body)
    parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def slack_text(payload)
    pretty = payload.is_a?(String) ? payload : JSON.pretty_generate(payload)
    pretty = "#{pretty[0, MAX_SLACK_TEXT]}\n… (truncated)" if pretty.length > MAX_SLACK_TEXT
    ":shopping_trolley: *Custom abandoned cart* (#{Rails.env})\n```#{pretty}```"
  end
end
