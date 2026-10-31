# frozen_string_literal: true

module Whatsapp
  module Ai
    module Config
      DEFAULT_MODEL = 'gpt-5.4-nano'
      DEFAULT_PRICES = { input: 0.20, cached: 0.02, output: 1.25 }.freeze

      module_function

      def api_key
        ENV.fetch("OPENAI_API_KEY", nil).presence
      end

      def model
        ENV.fetch("WHATSAPP_AI_MODEL", nil).presence || DEFAULT_MODEL
      end

      def reasoning_effort
        value = ENV.fetch("WHATSAPP_AI_REASONING_EFFORT", nil).to_s.strip
        value.empty? || value == 'default' ? nil : value
      end

      def enabled?
        api_key.present? && ENV.fetch("WHATSAPP_AI_DISABLED", nil).blank?
      end

      def price_per_million(kind)
        Float(ENV["WHATSAPP_AI_PRICE_#{kind.to_s.upcase}"].presence || DEFAULT_PRICES.fetch(kind))
      rescue ArgumentError, TypeError
        DEFAULT_PRICES.fetch(kind)
      end

      def cost_usd(input_tokens:, cached_tokens:, output_tokens:)
        uncached = [input_tokens.to_i - cached_tokens.to_i, 0].max
        ((uncached * price_per_million(:input)) +
          (cached_tokens.to_i * price_per_million(:cached)) +
          (output_tokens.to_i * price_per_million(:output))) / 1_000_000.0
      end
    end
  end
end
