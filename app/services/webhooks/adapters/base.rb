# frozen_string_literal: true

module Webhooks
  module Adapters
    class Base
      Normalized = Struct.new(
        :role,
        :event_type_key,
        :source_external_id,
        :dedup_key,
        :occurred_at,
        :phone,
        :country_code,
        :email,
        :first_name,
        :marketing_consent,
        :recovery_url,
        :total_price,
        :currency,
        :featured_image,
        :payload,
        :suppresses,
        :marks_recovered,
        :external_references,
        keyword_init: true
      ) do
        def trigger?
          role == :trigger
        end

        def suppress?
          role == :suppress
        end

        def sendable?
          phone.present? && (role != :trigger || recovery_url.present?)
        end
      end

      def self.call(provider:, event_name:, payload:, shop:, endpoint:)
        new(provider: provider, event_name: event_name, payload: payload, shop: shop, endpoint: endpoint).call
      end

      def initialize(provider:, event_name:, payload:, shop:, endpoint:)
        @provider = provider.to_s
        @event_name = event_name.to_s
        @payload = payload.is_a?(Hash) ? payload.deep_stringify_keys : {}
        @shop = shop
        @endpoint = endpoint
      end

      def call
        raise NotImplementedError
      end

      # Shopflo uses `event_name` on funnel events and `eventName` on
      # store_page_view, so detection has to live with the adapter.
      def self.event_name_from(payload)
        return nil unless payload.is_a?(Hash)

        body = payload.deep_stringify_keys
        (body['event_name'] || body['eventName'] || body['type'] || body['topic']).to_s.presence
      end

      private

      attr_reader :provider, :event_name, :payload, :shop, :endpoint

      def definition
        @definition ||= ::Webhooks::SourceRegistry.event(provider, event_name) || {}
      end

      def amount_scale
        @amount_scale ||= endpoint ? endpoint.amount_scale_for(event_name) : 1.0
      end

      def scaled(amount)
        return nil if amount.nil? || amount.to_s.strip.empty?

        (amount.to_f * amount_scale).round(2)
      end

      # Providers quote epoch MILLISECONDS. Read as seconds this puts every cart
      # in 1970 and makes every reminder stage instantly overdue.
      def parse_time(value)
        return nil if value.blank?
        return value if value.is_a?(Time) || value.is_a?(DateTime)

        if value.is_a?(Numeric) || value.to_s.match?(/\A\d{10,}\z/)
          numeric = value.to_i
          return numeric > 10_000_000_000 ? Time.zone.at(numeric / 1000.0) : Time.zone.at(numeric)
        end

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def first_present(*values)
        values.find { |value| value.to_s.strip.present? }.to_s.strip.presence
      end

      # DispatchEventJob needs an ISO country to repair bare local numbers
      # before Meta rejects them as INVALID_RECIPIENT.
      def derive_country_code(phone, *addresses)
        from_address = addresses.compact.map { |a| a['country_code'] }.find { |c| c.to_s.strip.present? }
        return from_address.to_s.strip.upcase if from_address.to_s.strip.present?
        return '' if phone.blank?

        parsed = Phonelib.parse(phone)
        parsed.valid? ? parsed.country.to_s.upcase : ''
      rescue StandardError
        ''
      end
    end
  end
end
