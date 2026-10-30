require 'razorpay'

module NetworkServices
  class PaymentProviderTestService < ApplicationService
    Result = Struct.new(:ok, :provider, :link, :mode, :message, keyword_init: true)

    TEST_AMOUNT = 1.0
    TEST_CUSTOMER = { name: 'COD King Test', email: 'test@codking.io', phone: '9999999999' }.freeze
    LINK_TTL = 30.minutes

    PROVIDER_LABELS = {
      'CASHFREE' => 'Cashfree', 'PAYU' => 'PayU', 'RAZORPAY' => 'Razorpay',
      'PHONEPE' => 'PhonePe', 'PAYMOB' => 'Paymob', 'GE_IDEA' => 'Geidea'
    }.freeze

    def initialize(shop, provider: nil, api_key: nil, api_secret: nil)
      @shop = shop
      setting = shop&.setting
      @provider   = (provider.presence || setting&.payment_provider).to_s.strip.upcase
      @provider   = 'RAZORPAY' if @provider.blank?
      @api_key    = (api_key.presence || setting&.payment_provider_api_key).to_s.strip
      @api_secret = (api_secret.presence || setting&.payment_provider_api_secret).to_s.strip
    end

    def call
      return failure('Enter your API key and secret first, then try again.') if @api_key.blank? || @api_secret.blank?

      case @provider
      when 'CASHFREE' then test_cashfree
      when 'PAYU'     then test_payu
      when 'RAZORPAY' then test_razorpay
      else
        failure("A one-click test link isn't available for #{provider_label} yet. Save your settings and create a test COD order to verify this provider.")
      end
    rescue => e
      Rails.logger.error("[PaymentProviderTestService] #{@provider} failed: #{e.class}: #{e.message}")
      failure("Couldn't create the test link: #{e.message}")
    end

    private

    def provider_label
      PROVIDER_LABELS[@provider] || @provider
    end

    def test_reference
      "CODKTEST#{SecureRandom.hex(6)}"
    end

    def test_cashfree
      credentials = Cashfree::Credentials.new(@api_key, @api_secret)
      return failure('Cashfree needs both an App ID and a Secret Key.') unless credentials.ready?

      body = {
        link_id: test_reference,
        link_amount: TEST_AMOUNT,
        link_currency: 'INR',
        link_purpose: 'COD King configuration test',
        link_partial_payments: false,
        link_expiry_time: (Time.now + LINK_TTL).iso8601,
        link_auto_reminders: false,
        customer_details: {
          customer_name: TEST_CUSTOMER[:name],
          customer_email: TEST_CUSTOMER[:email],
          customer_phone: TEST_CUSTOMER[:phone]
        },
        link_notify: { send_sms: false, send_email: false }
      }

      resp = HTTParty.post(
        "#{Cashfree::Api.pg_base}/links",
        body: body.to_json,
        headers: credentials.headers,
        timeout: 25
      )
      parsed = JSON.parse(resp.body || '{}') rescue {}

      if resp.success? && parsed['link_url'].present?
        success(parsed['link_url'], Cashfree::Api.mode)
      else
        failure(parsed['message'].presence || "Cashfree rejected the request (HTTP #{resp.code}). Check your App ID and Secret Key.", Cashfree::Api.mode)
      end
    end

    def test_payu
      credentials = Payu::Credentials.new(@api_key, @api_secret)
      return failure('PayU needs a Merchant Key, Client ID and Client Secret.') unless credentials.links_ready?

      token = Payu::AccessTokenService.call(credentials)
      return failure('PayU sign-in failed. Check the Client ID / Client Secret and that the "create_payment_links" scope is enabled.', Payu::Api.mode) if token.blank?

      body = {
        subAmount: TEST_AMOUNT,
        isAmountFilledByCustomer: false,
        description: 'COD King configuration test',
        source: 'API',
        invoiceNumber: test_reference,
        maxPaymentsAllowed: 1,
        expiryDate: (Time.now + LINK_TTL).strftime('%Y-%m-%d %H:%M:%S'),
        customer: {
          name: TEST_CUSTOMER[:name],
          email: TEST_CUSTOMER[:email],
          phone: TEST_CUSTOMER[:phone]
        }
      }

      resp = HTTParty.post(
        "#{Payu::Api.oneapi_base}/payment-links",
        body: body.to_json,
        headers: {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{token}",
          'merchantId' => credentials.merchant_id
        },
        timeout: 25
      )
      parsed = JSON.parse(resp.body || '{}') rescue {}
      link = parsed.dig('result', 'paymentLink')

      if resp.success? && link.present?
        success(link, Payu::Api.mode)
      else
        # A wrong/missing merchantId makes PayU return an empty HTTP 200, so an
        # authenticated-but-linkless response points at the Merchant ID.
        failure(parsed['message'].presence || "PayU didn't return a link (HTTP #{resp.code}). The most common cause is a wrong Merchant ID.", Payu::Api.mode)
      end
    end

    def test_razorpay
      Razorpay.setup(@api_key, @api_secret)
      Razorpay.headers = { 'Content-type' => 'application/json' }

      params = {
        amount: (TEST_AMOUNT * 100).to_i,
        currency: 'INR',
        accept_partial: false,
        description: 'COD King configuration test',
        expire_by: (Time.now + LINK_TTL).to_i,
        customer: {
          name: TEST_CUSTOMER[:name],
          email: TEST_CUSTOMER[:email],
          contact: TEST_CUSTOMER[:phone]
        },
        notify: { sms: false, email: false }
      }

      resp = Razorpay::PaymentLink.create(params.to_json)
      if resp&.short_url.present?
        success(resp.short_url, razorpay_mode)
      else
        failure('Razorpay did not return a link. Check your Key ID and Key Secret.', razorpay_mode)
      end
    rescue Razorpay::Error => e
      failure("Razorpay rejected the credentials: #{e.message}", razorpay_mode)
    end

    def razorpay_mode
      @api_key.to_s.start_with?('rzp_live') ? 'prod' : 'test'
    end

    def success(link, mode)
      Result.new(ok: true, provider: @provider, link: link, mode: mode.to_s, message: "Success — #{provider_label} is configured correctly. Open the link below to confirm the checkout page loads.")
    end

    def failure(message, mode = nil)
      Result.new(ok: false, provider: @provider, link: nil, mode: mode.to_s, message: message)
    end
  end
end
