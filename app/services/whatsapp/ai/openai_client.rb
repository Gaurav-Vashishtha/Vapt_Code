# frozen_string_literal: true

module Whatsapp
  module Ai
    class OpenaiClient
      class Error < StandardError
        attr_reader :status

        def initialize(message, status = nil)
          super(message)
          @status = status
        end
      end

      ENDPOINT = 'https://api.openai.com/v1/chat/completions'
      TIMEOUT = 25
      MAX_COMPLETION_TOKENS = 2000
      RETRYABLE = [429, 500, 502, 503, 504].freeze

      def initialize(api_key: Config.api_key, model: Config.model)
        @api_key = api_key
        @model = model
      end

      attr_reader :model

      def chat(messages:, tools:, tool_choice: 'required')
        raise Error, 'OPENAI_API_KEY is not set' if @api_key.blank?

        body = {
          model: @model,
          messages: messages,
          tools: tools,
          tool_choice: tool_choice,
          parallel_tool_calls: false,
          max_completion_tokens: MAX_COMPLETION_TOKENS
        }
        body[:reasoning_effort] = Config.reasoning_effort if Config.reasoning_effort
        post_with_fallbacks(body)
      end

      private

      def post_with_fallbacks(body)
        post_with_retry(body)
      rescue Error => e
        if body.key?(:reasoning_effort) && e.message.include?('reasoning_effort')
          Rails.logger.warn("[Whatsapp::Ai::OpenaiClient] #{@model} rejected reasoning_effort, retrying without it")
          return post_with_fallbacks(body.except(:reasoning_effort))
        end
        raise unless images?(body[:messages]) && e.message.match?(/image/i)

        Rails.logger.warn("[Whatsapp::Ai::OpenaiClient] #{@model} rejected image input, retrying text only")
        post_with_fallbacks(body.merge(messages: without_images(body[:messages])))
      end

      def images?(messages)
        Array(messages).any? { |m| m[:content].is_a?(Array) }
      end

      def without_images(messages)
        Array(messages).map do |m|
          next m unless m[:content].is_a?(Array)

          text = m[:content].filter_map { |part| part[:text] if part[:type] == 'text' }.join("\n")
          m.merge(content: "#{text} [Photo]".strip)
        end
      end

      def post_with_retry(body)
        attempts = 0
        begin
          attempts += 1
          post(body)
        rescue Error => e
          raise unless attempts < 2 && (e.status.nil? || RETRYABLE.include?(e.status))

          sleep(1.5)
          retry
        end
      end

      def post(body)
        response = HTTParty.post(
          ENDPOINT,
          headers: { 'Authorization' => "Bearer #{@api_key}", 'Content-Type' => 'application/json' },
          body: body.to_json,
          timeout: TIMEOUT
        )
        data = JSON.parse(response.body.to_s.presence || '{}')
        unless response.code.to_i.between?(200, 299)
          raise Error.new(data.dig('error', 'message').presence || "OpenAI HTTP #{response.code}", response.code.to_i)
        end

        data
      rescue JSON::ParserError
        raise Error.new("OpenAI returned an unreadable response (HTTP #{response&.code})", response&.code.to_i)
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
        raise Error.new("Could not reach OpenAI: #{e.class}")
      end
    end
  end
end
