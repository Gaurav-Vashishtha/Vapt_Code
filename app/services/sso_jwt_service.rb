require 'jwt'

class SsoJwtService
  class MissingSecretError < StandardError; end

  ALGORITHM = 'HS256'.freeze
  LIFETIME = 30.days
  ABSOLUTE_LIFETIME = 90.days

  class << self
    # Issue a fresh token. If `iat` is provided, the new exp is capped at
    # iat + ABSOLUTE_LIFETIME so renewal can't extend a session past the hard cap.
    def issue(phone:, country_code:, iat: nil)
      anchor = iat ? Time.at(iat.to_i) : Time.current
      hard_cap = anchor + ABSOLUTE_LIFETIME
      exp = [LIFETIME.from_now, hard_cap].min
      payload = {
        phone: phone,
        country_code: country_code,
        iat: anchor.to_i,
        exp: exp.to_i
      }
      JWT.encode(payload, secret, ALGORITHM)
    end

    # Decode and verify. Returns a symbol-keyed hash on success, nil on
    # invalid signature / malformed / expired tokens.
    def decode(token)
      return nil if token.blank?

      payload, _header = JWT.decode(token, secret, true, algorithm: ALGORITHM)
      payload.symbolize_keys
    rescue JWT::DecodeError
      nil
    end

    private

    def secret
      ENV['JWT_SSO_SECRET'].presence || raise(MissingSecretError, 'JWT_SSO_SECRET env var is not set')
    end
  end
end
