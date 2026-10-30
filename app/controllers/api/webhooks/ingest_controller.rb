# frozen_string_literal: true

module Api
  module Webhooks
    class IngestController < ApplicationController
      skip_before_action :verify_authenticity_token, only: [:create]

      MAX_BODY_BYTES = ENV.fetch('WEBHOOK_MAX_BODY_BYTES', 262_144).to_i
      MAX_EVENTS_PER_REQUEST = 50

      def create
        endpoint = find_endpoint
        # Same response for "no such token" and "disabled" so the endpoint can't
        # be used to probe which tokens exist.
        return render(json: { error: 'not found' }, status: :not_found) if endpoint.nil?

        raw_body = request.raw_post.to_s
        if raw_body.bytesize > MAX_BODY_BYTES
          return render(json: { error: 'payload too large' }, status: :payload_too_large)
        end

        verification = ::Webhooks::SignatureVerifier.call(endpoint: endpoint, request: request, raw_body: raw_body)
        unless verification.ok?
          Rails.logger.warn(
            "[webhook/ingest] shop=#{endpoint.shop_id} provider=#{endpoint.provider} rejected: #{verification.reason}"
          )
          return render(json: { error: 'unauthorized' }, status: :unauthorized)
        end

        events = extract_events(raw_body)
        return render(json: { error: 'invalid json body' }, status: :bad_request) if events.nil?
        return render(json: { ok: true, accepted: 0 }, status: :ok) if events.empty?

        accepted = 0
        duplicates = 0

        events.first(MAX_EVENTS_PER_REQUEST).each do |body|
          case record_event(endpoint, body)
          when :accepted  then accepted += 1
          when :duplicate then duplicates += 1
          end
        end

        endpoint.record_receipt! if accepted.positive? || duplicates.positive?

        render json: { ok: true, accepted: accepted, duplicates: duplicates }, status: :ok
      rescue StandardError => e
        # Shopflo has not documented its retry semantics, so a 500 here risks a
        # retry storm. Acknowledge and let the log carry the failure.
        Rails.logger.error("[webhook/ingest] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        render json: { ok: false, error: 'internal error' }, status: :ok
      end

      private

      def find_endpoint
        provider = params[:provider].to_s
        token = params[:endpoint_token].to_s
        return nil if provider.blank? || token.blank?
        return nil unless ::Webhooks::SourceRegistry.provider?(provider)

        WebhookEndpoint.enabled.find_by(provider: provider, endpoint_token: token)
      end

      def extract_events(raw_body)
        return [] if raw_body.blank?

        parsed = JSON.parse(raw_body)
        case parsed
        when Hash  then [parsed]
        when Array then parsed.select { |entry| entry.is_a?(Hash) }
        else []
        end
      rescue JSON::ParserError
        nil
      end

      def record_event(endpoint, body)
        adapter = ::Webhooks::SourceRegistry.adapter_for(endpoint.provider)
        event_name = adapter&.event_name_from(body)
        dedup_key = adapter.respond_to?(:dedup_key_for) ? adapter.dedup_key_for(event_name, body) : nil

        record = InboundWebhookEvent.create!(
          shop_id: endpoint.shop_id,
          webhook_endpoint: endpoint,
          provider: endpoint.provider,
          event_name: event_name,
          dedup_key: dedup_key,
          payload: body,
          status: :received,
          received_at: Time.current
        )

        ::Webhooks::ProcessInboundEventJob.perform_async(record.id)
        :accepted
      rescue ActiveRecord::RecordNotUnique
        Rails.logger.info("[webhook/ingest] shop=#{endpoint.shop_id} duplicate delivery #{dedup_key}")
        :duplicate
      rescue StandardError => e
        Rails.logger.error("[webhook/ingest] shop=#{endpoint.shop_id} failed to record: #{e.class}: #{e.message}")
        :failed
      end
    end
  end
end
