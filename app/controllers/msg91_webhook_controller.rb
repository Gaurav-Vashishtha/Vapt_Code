# frozen_string_literal: true

# MSG91 WhatsApp delivery reports ("Webhook (New)" in the MSG91 dashboard, on
# COD King's account). Configure it to POST here with a custom header
#   X-Webhook-Token: <MSG91_WEBHOOK_TOKEN>
# (or ?token=<MSG91_WEBHOOK_TOKEN> on the URL). Events are processed in the
# background so MSG91 always gets a fast 200; a 4xx would auto-pause the webhook.
class Msg91WebhookController < ApplicationController
  skip_before_action :verify_authenticity_token

  def whatsapp
    return head :unauthorized unless authorized?

    events = extract_events(request.raw_post)
    Whatsapp::Msg91DeliveryReportJob.perform_async(events.to_json) if events.any?
    head :ok
  rescue JSON::ParserError
    head :ok
  end

  private

  def authorized?
    expected = ENV['MSG91_WEBHOOK_TOKEN'].to_s
    given = request.headers['X-Webhook-Token'].presence || params[:token].to_s
    expected.present? && ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected)
  end

  # MSG91 posts one event per recipient; accept a bare object, an array, or
  # an object wrapping them under "data".
  def extract_events(raw)
    data = JSON.parse(raw.presence || '{}')
    list = data.is_a?(Hash) && data['data'].is_a?(Array) ? data['data'] : Array.wrap(data)
    list.select { |e| e.is_a?(Hash) }
        .map { |e| e.slice('eventName', 'reason', 'requestId', 'uuid', 'crqid', 'oneApiRequestId', 'direction', 'customerNumber') }
  end
end
