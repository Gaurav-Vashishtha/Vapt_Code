module Meta
  class PhoneNumberService < ApplicationService
    class Error < StandardError; end

    OPERATIONS = %i[register request_code verify_code status].freeze

    def initialize(account:, operation:, pin: nil, code_method: 'SMS', language: 'en', code: nil)
      raise ArgumentError, "unknown operation #{operation}" unless OPERATIONS.include?(operation)

      @account = account
      @operation = operation
      @pin = pin
      @code_method = code_method
      @language = language
      @code = code
    end

    def call
      raise Error, 'no phone_number_id on account' if account.phone_number_id.blank?

      result = send(operation)
      account.update(last_synced_at: Time.current) if result
      result
    rescue Meta::GraphClient::Error => e
      raise Error, e.message
    end

    private

    attr_reader :account, :operation, :pin, :code_method, :language, :code

    # Two-factor PIN registration. Required for cloud-hosted numbers: Meta
    # returns 133010 on every send until this call succeeds, even though the
    # number already reports code_verification_status VERIFIED. The PIN is kept
    # (encrypted) because Meta demands the SAME PIN on any later re-register.
    def register
      raise Error, 'pin is required (6 digits)' unless pin.to_s.match?(/\A\d{6}\z/)

      account.graph_client.post(
        "#{account.phone_number_id}/register",
        body: { messaging_product: 'whatsapp', pin: pin }
      )
      account.mark_registered!(pin: pin)
      { ok: true }
    end

    # Request a verification code via SMS or voice for unregistered numbers.
    def request_code
      account.graph_client.post(
        "#{account.phone_number_id}/request_code",
        body: { code_method: code_method, language: language }
      )
      { ok: true, code_method: code_method }
    end

    def verify_code
      raise Error, 'code is required' if code.blank?

      account.graph_client.post(
        "#{account.phone_number_id}/verify_code",
        body: { code: code }
      )
      { ok: true }
    end

    STATUS_FIELDS = 'id,display_phone_number,verified_name,code_verification_status,quality_rating,status'

    def status
      data = fetch_status

      verified = data['code_verification_status'] == 'VERIFIED'
      account.update(
        display_phone_number: data['display_phone_number'],
        verified_name: data['verified_name'],
        status: verified ? :verified : :pending_verification
      )
      account.record_quality!(data['quality_rating'], limit_tier: data['messaging_limit_tier'])
      account.apply_platform_status!(data['status'])

      {
        code_verification_status: data['code_verification_status'],
        quality_rating: data['quality_rating'],
        messaging_limit_tier: data['messaging_limit_tier'],
        display_phone_number: data['display_phone_number'],
        verified_name: data['verified_name'],
        platform_status: data['status'],
        registered_at: account.registered_at
      }
    end

    # Meta now sets messaging limits per business portfolio; if the phone-level
    # field is ever removed (#100 nonexisting field) the status sync must still work.
    def fetch_status
      account.graph_client.get(account.phone_number_id, query: { fields: "#{STATUS_FIELDS},messaging_limit_tier" })
    rescue Meta::GraphClient::Error => e
      raise unless e.code.to_i == 100

      account.graph_client.get(account.phone_number_id, query: { fields: STATUS_FIELDS })
    end
  end
end
