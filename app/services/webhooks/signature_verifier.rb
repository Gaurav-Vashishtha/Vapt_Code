# frozen_string_literal: true

module Webhooks
  # Deliberately not built on ShippingApi::OriginValidator: that one fails OPEN
  # when SHIPPING_API_ALLOWED_ORIGINS is blank and SHIPPING_API_REQUIRE_SECRET
  # is not "true", which is fine for a Slack relay and not fine for an endpoint
  # that triggers billable sends. An unknown scheme here is a rejection.
  class SignatureVerifier
    Result = Struct.new(:ok, :reason, keyword_init: true) do
      def ok?
        !!ok
      end
    end

    def self.call(endpoint:, request:, raw_body:)
      new(endpoint: endpoint, request: request, raw_body: raw_body).call
    end

    def initialize(endpoint:, request:, raw_body:)
      @endpoint = endpoint
      @request = request
      @raw_body = raw_body.to_s
    end

    def call
      case @endpoint.signature_scheme.to_s
      when 'none'          then Result.new(ok: true)
      when 'shared_secret' then verify_shared_secret
      when 'hmac_sha256'   then verify_hmac
      else Result.new(ok: false, reason: "unknown signature scheme #{@endpoint.signature_scheme}")
      end
    end

    private

    def secret
      @secret ||= @endpoint.secret.to_s
    end

    def verify_shared_secret
      return Result.new(ok: false, reason: 'endpoint has no secret') if secret.blank?

      candidates = [header_value, bearer_token].compact_blank
      return Result.new(ok: false, reason: 'missing signature header') if candidates.empty?
      return Result.new(ok: true) if candidates.any? { |candidate| secure_compare(candidate, secret) }

      Result.new(ok: false, reason: 'shared secret mismatch')
    end

    def verify_hmac
      return Result.new(ok: false, reason: 'endpoint has no secret') if secret.blank?

      provided = header_value.to_s.sub(/\Asha256=/i, '').strip
      return Result.new(ok: false, reason: 'missing signature header') if provided.blank?

      digest = OpenSSL::HMAC.digest('SHA256', secret, @raw_body)
      # Shopflo has not documented an encoding; accept either rather than
      # rejecting a signature that is actually valid.
      expected = [Digest.hexencode(digest), Base64.strict_encode64(digest)]
      return Result.new(ok: true) if expected.any? { |candidate| secure_compare(provided, candidate) }

      Result.new(ok: false, reason: 'hmac mismatch')
    end

    def header_value
      name = @endpoint.signature_header.presence || 'X-Webhook-Signature'
      @request.headers[name] || @request.headers["HTTP_#{name.tr('-', '_').upcase}"]
    end

    def bearer_token
      auth = @request.headers['Authorization'].to_s
      return nil unless auth.downcase.start_with?('bearer ')

      auth.split(' ', 2).last.to_s.strip
    end

    # Hashed first because fixed_length_secure_compare raises on length mismatch.
    def secure_compare(left, right)
      ActiveSupport::SecurityUtils.fixed_length_secure_compare(
        Digest::SHA256.digest(left.to_s),
        Digest::SHA256.digest(right.to_s)
      )
    end
  end
end
