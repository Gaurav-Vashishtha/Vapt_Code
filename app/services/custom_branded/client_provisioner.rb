# frozen_string_literal: true

module CustomBranded
  # Finds or creates the CustomBrandedClient behind a branded-portal domain.
  # Creation only ever happens through the signature-gated portal
  # (BaseController) — the public API authenticates by key and always finds.
  # No shops row, no Setting, no Shopify anything.
  class ClientProvisioner < ApplicationService
    class InvalidDomain < StandardError; end

    def initialize(domain:)
      @raw_domain = domain
    end

    def call
      domain = normalize!(@raw_domain)

      client = CustomBrandedClient.find_by(domain: domain)
      return client if client

      client = CustomBrandedClient.create!(domain: domain)
      SlackNotifyJob.perform_async(
        ":new: Custom-branded client provisioned (#{Rails.env}) domain=#{domain}"
      )
      client
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # Concurrent first-hit race — the other request won; use its row.
      existing = CustomBrandedClient.find_by(domain: normalize!(@raw_domain))
      raise InvalidDomain, e.message if existing.nil?

      existing
    end

    private

    def normalize!(value)
      domain = CustomBrandedClient.normalize_domain(value)
      unless domain.match?(CustomBrandedClient::DOMAIN_FORMAT) && domain.length <= 255
        raise InvalidDomain, "invalid domain #{value.inspect}"
      end

      domain
    end
  end
end
