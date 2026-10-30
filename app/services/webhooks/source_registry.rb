# frozen_string_literal: true

module Webhooks
  class SourceRegistry
    SOURCES = {
      'shopflo' => {
        label: 'Shopflo',
        description: 'Shop Pass webhook events from the Shopflo checkout.',
        adapter: 'Webhooks::Adapters::Shopflo',
        events: {
          'checkout_abandoned' => {
            label: 'Checkout abandoned',
            description: 'Buyer reached the Shopflo checkout and did not complete the order.',
            role: :trigger,
            event_type_key: 'abandoned_cart',
            default_enabled: false,
            default_amount_scale: 1.0
          },
          'added_to_cart_ui' => {
            label: 'Added to cart',
            description: 'Buyer added an item but never reached checkout. High volume.',
            role: :trigger,
            event_type_key: 'cart_abandoned',
            default_enabled: false,
            # Shopflo quotes this event in paise while checkout_abandoned quotes
            # rupees; unconfirmed by them, so it stays overridable per endpoint.
            default_amount_scale: 0.01
          },
          'product_page_viewed' => {
            label: 'Product page viewed',
            description: 'Browse abandonment. Very high volume — enable only after measuring.',
            role: :trigger,
            event_type_key: 'browse_abandoned',
            default_enabled: false,
            default_amount_scale: 1.0
          },
          'checkout_clicked' => {
            label: 'Checkout clicked',
            description: 'Buyer progressed to checkout — suppresses earlier-funnel nudges.',
            role: :suppress,
            suppresses: %w[cart_abandoned browse_abandoned],
            marks_recovered: false,
            default_enabled: true
          },
          'order_completed' => {
            label: 'Order completed',
            description: 'Order placed — suppresses every pending reminder and marks the cart recovered.',
            role: :suppress,
            suppresses: %w[abandoned_cart cart_abandoned browse_abandoned],
            marks_recovered: true,
            default_enabled: true
          },
          'collection_page_viewed' => { label: 'Collection page viewed', role: :ignore, default_enabled: false },
          'store_page_view'        => { label: 'Store page view',        role: :ignore, default_enabled: false }
        }
      },

      'custom' => {
        label: 'Custom / other',
        description: 'Generic endpoint for a partner posting Shopflo-shaped events.',
        adapter: 'Webhooks::Adapters::Shopflo',
        events: {
          'checkout_abandoned' => {
            label: 'Checkout abandoned',
            role: :trigger,
            event_type_key: 'abandoned_cart',
            default_enabled: false,
            default_amount_scale: 1.0
          },
          'order_completed' => {
            label: 'Order completed',
            role: :suppress,
            suppresses: %w[abandoned_cart cart_abandoned browse_abandoned],
            marks_recovered: true,
            default_enabled: true
          }
        }
      }
    }.freeze

    class << self
      def providers
        SOURCES.keys
      end

      def provider?(name)
        SOURCES.key?(name.to_s)
      end

      def provider(name)
        SOURCES[name.to_s]
      end

      def events_for(provider_name)
        provider(provider_name)&.dig(:events) || {}
      end

      def event(provider_name, event_name)
        events_for(provider_name)[event_name.to_s]
      end

      def adapter_for(provider_name)
        provider(provider_name)&.dig(:adapter)&.constantize
      end

      def event_type_key_for(provider_name, event_name)
        event(provider_name, event_name)&.dig(:event_type_key)
      end

      def role_for(provider_name, event_name)
        event(provider_name, event_name)&.dig(:role) || :ignore
      end

      def as_json(*)
        SOURCES.map do |key, config|
          {
            key: key,
            label: config[:label],
            description: config[:description],
            events: config[:events].map do |event_name, definition|
              {
                name: event_name,
                label: definition[:label],
                description: definition[:description],
                role: definition[:role].to_s,
                eventTypeKey: definition[:event_type_key],
                defaultEnabled: !!definition[:default_enabled],
                defaultAmountScale: (definition[:default_amount_scale] || 1.0).to_f,
                suppresses: Array(definition[:suppresses])
              }
            end
          }
        end
      end
    end
  end
end
