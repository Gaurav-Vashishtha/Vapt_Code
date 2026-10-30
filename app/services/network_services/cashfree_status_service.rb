module NetworkServices
  class CashfreeStatusService < ApplicationService
    attr_reader :shop, :order_confirmation

    # NetworkServices::CashfreeStatusService.call(Shop.last, OrderConfirmation.last)
    def initialize(shop, order_confirmation, test = false)
      @shop = shop
      @order_confirmation = order_confirmation
      @test = test
    end

    def call
      return false if order_confirmation.blank?

      credentials = Cashfree::Credentials.for(shop.setting)
      return false unless credentials.ready?

      link_ids = order_confirmation.phonepe_transaction_ids.to_s.split(',').map(&:strip).reject(&:blank?)
      return false if link_ids.empty?

      link_ids.any? { |link_id| paid?(credentials, link_id) }
    rescue => e
      Rails.logger.error("[CashfreeStatusService] order=#{order_confirmation&.id} verify failed: #{e.class}: #{e.message}")
      false
    end

    private

    def paid?(credentials, link_id)
      resp = HTTParty.get(
        "#{Cashfree::Api.pg_base}/links/#{link_id}",
        headers: credentials.headers,
        timeout: 20
      )
      return false unless resp.success?

      parsed = JSON.parse(resp.body || '{}') rescue {}
      parsed['link_status'].to_s.upcase == 'PAID'
    rescue => e
      Rails.logger.error("[CashfreeStatusService] order=#{order_confirmation&.id} link=#{link_id} fetch failed: #{e.class}: #{e.message}")
      false
    end
  end
end
