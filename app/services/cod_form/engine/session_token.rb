# frozen_string_literal: true

require "json"
require "openssl"
require "base64"

module CodForm
  module Engine
    # Signed form session token (ARCHITECTURE E.12, FRD-4, NFR-6). No clock: time is passed in.
    class SessionToken
      VERSION = "v1"

      class << self
        # => "v1.<b64url(payload)>.<b64url(sig)>"
        def issue(secret:, shop_id:, session_id:, issued_at:, ttl_seconds: 7200, test: false)
          payload = { "sid" => session_id.to_s, "shp" => shop_id.to_i, "iat" => issued_at.to_i,
                      "exp" => issued_at.to_i + ttl_seconds.to_i, "t" => test == true }
          body = "#{VERSION}.#{encode(JSON.generate(payload))}"
          "#{body}.#{encode(sign(secret, body))}"
        end

        # => {"ok"=>true,"shop_id","session_id","issued_at","expires_at","test"} | {"ok"=>false,"error"=>...}
        def verify(secret:, token:, now:)
          parts = token.to_s.split(".", -1)
          return error("malformed") unless parts.length == 3 && parts[0] == VERSION && parts.none?(&:empty?)

          signature = decode(parts[2])
          return error("malformed") if signature.nil?

          expected = sign(secret, "#{parts[0]}.#{parts[1]}")
          unless signature.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(signature, expected)
            return error("bad_signature")
          end

          json = decode(parts[1])
          payload = json && begin
            JSON.parse(json)
          rescue JSON::ParserError
            nil
          end
          unless payload.is_a?(Hash) && payload["sid"].is_a?(String) && payload["shp"].is_a?(Integer) &&
                 payload["iat"].is_a?(Integer) && payload["exp"].is_a?(Integer)
            return error("malformed")
          end
          return error("expired") if now.to_i >= payload["exp"]

          { "ok" => true, "shop_id" => payload["shp"], "session_id" => payload["sid"],
            "issued_at" => payload["iat"], "expires_at" => payload["exp"], "test" => payload["t"] == true }
        end

        private

        def sign(secret, body)
          OpenSSL::HMAC.digest("SHA256", secret.to_s, body)
        end

        def encode(bytes)
          Base64.urlsafe_encode64(bytes, padding: false)
        end

        def decode(text)
          return nil unless text.match?(/\A[A-Za-z0-9_-]+\z/)

          Base64.urlsafe_decode64(text)
        rescue ArgumentError
          nil
        end

        def error(code)
          { "ok" => false, "error" => code }
        end
      end
    end
  end
end
