# frozen_string_literal: true

module Api
  module Webhooks
    class EndpointsController < AuthenticatedController
      DELIVERY_PAGE_SIZE = 25

      def index
        render json: {
          providers: ::Webhooks::SourceRegistry.as_json,
          endpoints: @shop.webhook_endpoints.order(:provider).map { |e| serialize(e) }
        }
      end

      def create
        provider = params[:provider].to_s.presence || 'shopflo'
        existing = @shop.webhook_endpoints.find_by(provider: provider)
        return render(json: { endpoint: serialize(existing) }, status: :ok) if existing

        endpoint = @shop.webhook_endpoints.new(
          provider: provider,
          enabled: true,
          signature_scheme: params[:signature_scheme].presence || 'shared_secret',
          signature_header: params[:signature_header].presence || 'X-Webhook-Signature',
          event_config: default_event_config(provider)
        )

        if endpoint.save
          render json: { endpoint: serialize(endpoint, reveal_secret: true) }, status: :created
        else
          render json: { error: endpoint.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      end

      def update
        endpoint = @shop.webhook_endpoints.find_by(id: params[:id])
        return render(json: { error: 'not found' }, status: :not_found) unless endpoint

        attrs = {}
        attrs[:enabled] = ActiveModel::Type::Boolean.new.cast(params[:enabled]) unless params[:enabled].nil?
        attrs[:mirror_to_slack] = ActiveModel::Type::Boolean.new.cast(params[:mirror_to_slack]) unless params[:mirror_to_slack].nil?
        attrs[:signature_scheme] = params[:signature_scheme] if params[:signature_scheme].present?
        attrs[:signature_header] = params[:signature_header] if params[:signature_header].present?

        if params[:event_config].present?
          attrs[:event_config] = sanitize_event_config(endpoint, params[:event_config])
        end

        if endpoint.update(attrs)
          render json: { endpoint: serialize(endpoint) }
        else
          render json: { error: endpoint.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      end

      def destroy
        endpoint = @shop.webhook_endpoints.find_by(id: params[:id])
        return render(json: { error: 'not found' }, status: :not_found) unless endpoint

        endpoint.destroy
        render json: { ok: true }
      end

      def rotate_secret
        endpoint = @shop.webhook_endpoints.find_by(id: params[:id])
        return render(json: { error: 'not found' }, status: :not_found) unless endpoint

        endpoint.rotate_secret!
        render json: { endpoint: serialize(endpoint, reveal_secret: true) }
      end

      def deliveries
        scope = @shop.inbound_webhook_events.recent
        scope = scope.where(webhook_endpoint_id: params[:endpoint_id]) if params[:endpoint_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?

        render json: {
          deliveries: scope.limit(DELIVERY_PAGE_SIZE).map { |event| serialize_delivery(event) }
        }
      end

      def replay
        event = @shop.inbound_webhook_events.find_by(id: params[:id])
        return render(json: { error: 'not found' }, status: :not_found) unless event

        event.update!(status: :received, error: nil, skip_reason: nil, processed_at: nil)
        ::Webhooks::ProcessInboundEventJob.perform_async(event.id)
        render json: { ok: true }
      end

      private

      def default_event_config(provider)
        ::Webhooks::SourceRegistry.events_for(provider).each_with_object({}) do |(name, definition), acc|
          acc[name] = {
            'enabled' => !!definition[:default_enabled],
            'amount_scale' => (definition[:default_amount_scale] || 1.0).to_f
          }
        end
      end

      def sanitize_event_config(endpoint, raw)
        known = ::Webhooks::SourceRegistry.events_for(endpoint.provider).keys
        permitted = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw

        permitted.each_with_object(endpoint.event_config.dup) do |(name, settings), acc|
          next unless known.include?(name.to_s)
          next unless settings.is_a?(Hash)

          current = acc[name.to_s] || {}
          current['enabled'] = ActiveModel::Type::Boolean.new.cast(settings['enabled']) unless settings['enabled'].nil?

          if settings['amount_scale'].present?
            scale = settings['amount_scale'].to_f
            current['amount_scale'] = scale.positive? ? scale : 1.0
          end

          acc[name.to_s] = current
        end
      end

      def serialize(endpoint, reveal_secret: false)
        events = ::Webhooks::SourceRegistry.events_for(endpoint.provider).map do |name, definition|
          settings = endpoint.event_settings(name)
          {
            name: name,
            label: definition[:label],
            description: definition[:description],
            role: definition[:role].to_s,
            eventTypeKey: definition[:event_type_key],
            enabled: !!settings['enabled'],
            amountScale: settings['amount_scale'].to_f
          }
        end

        {
          id: endpoint.id,
          provider: endpoint.provider,
          enabled: endpoint.enabled,
          url: endpoint.ingest_url,
          signatureScheme: endpoint.signature_scheme,
          signatureHeader: endpoint.signature_header,
          mirrorToSlack: endpoint.mirror_to_slack,
          lastReceivedAt: endpoint.last_received_at,
          counters: endpoint.counters,
          events: events,
          # The full secret is returned only on create and rotate, which are the
          # two moments the merchant can still copy it somewhere.
          secret: reveal_secret ? endpoint.secret : nil,
          secretHint: endpoint.secret.to_s.last(4)
        }
      end

      def serialize_delivery(event)
        {
          id: event.id,
          provider: event.provider,
          eventName: event.event_name,
          status: event.status,
          skipReason: event.skip_reason,
          error: event.error,
          internalEventTypeKey: event.internal_event_type_key,
          receivedAt: event.received_at,
          processedAt: event.processed_at,
          payload: event.payload
        }
      end
    end
  end
end
